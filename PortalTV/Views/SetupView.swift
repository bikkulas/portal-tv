//
//  SetupView.swift
//  PortalTV
//
//  Portal address + MAC address, with a connection test that reads the
//  account profile back from the portal before anything is saved.
//

import SwiftUI

struct SetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isFirstRun: Bool

    @State private var portalURL: String = ""
    @State private var macAddress: String = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var succeeded = false

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Portal TV")
                    .font(.largeTitle.bold())
                Text(isFirstRun
                    ? "Enter the portal address and the MAC address your provider registered. Nothing is saved until the portal accepts them."
                    : "Change the portal or MAC address. Reconnecting replaces the channel list.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let accountInfo = store.accountInfo, !isFirstRun {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current account")
                            .font(.headline)
                        if let expiry = accountInfo.expiryDate {
                            Text("Expires: \(expiry)")
                        }
                        if let status = accountInfo.status {
                            Text("Status: \(status)")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(width: 560)

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Portal URL")
                        .font(.headline)
                    TextField("http://portal.example.com/c/", text: $portalURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("MAC address")
                        .font(.headline)
                    TextField("00:1A:79:XX:XX:XX", text: $macAddress)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Text("Use the MAC your provider registered. Only generate a new one if they let you register it yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Button {
                        Task { await connect() }
                    } label: {
                        if isWorking {
                            Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
                        } else {
                            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .disabled(isWorking || !canConnect)

                    Button("Generate MAC") {
                        macAddress = StalkerMAC.generate()
                    }
                    .disabled(isWorking)

                    if !isFirstRun {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isWorking)
                    }
                }

                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(succeeded ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !isFirstRun {
                    Divider()
                    Button(role: .destructive) {
                        store.disconnect()
                        dismiss()
                    } label: {
                        Label("Forget this portal", systemImage: "trash")
                    }
                    .disabled(isWorking)
                }
                Spacer()
            }
            .frame(maxWidth: 900)
        }
        .padding(60)
        .onAppear {
            if let profile = store.profile {
                portalURL = profile.portalURL
                macAddress = profile.macAddress
            }
        }
    }

    private var canConnect: Bool {
        !portalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && StalkerMAC.normalize(macAddress) != nil
    }

    private func connect() async {
        guard let mac = StalkerMAC.normalize(macAddress) else {
            succeeded = false
            message = "That doesn't look like a MAC address. Expected six pairs of hex digits, e.g. 00:1A:79:12:34:56."
            return
        }
        macAddress = mac
        let profile = PortalProfile(
            portalURL: portalURL.trimmingCharacters(in: .whitespacesAndNewlines),
            macAddress: mac
        )
        isWorking = true
        message = "Contacting the portal…"
        succeeded = false
        let ok = await store.connect(to: profile)
        isWorking = false
        if ok {
            succeeded = true
            var parts = ["Connected. \(store.channels.count) channels loaded."]
            if let expiry = store.accountInfo?.expiryDate {
                parts.append("Account expires \(expiry).")
            }
            message = parts.joined(separator: " ")
            if !isFirstRun {
                dismiss()
            }
        } else {
            succeeded = false
            if case let .failed(reason) = store.phase {
                message = reason
            } else {
                message = "The portal didn't accept the connection."
            }
        }
    }
}
