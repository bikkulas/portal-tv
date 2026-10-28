//
//  PlayerView.swift
//  PortalTV
//
//  Full-screen live playback. Resolves the channel's short-lived stream URL
//  through the portal, hands it to KSPlayer, and maps the Siri Remote:
//    up / down     – previous / next channel in the current list
//    left / right  – show the info overlay
//    select        – toggle the info overlay
//    play/pause    – pause / resume
//    menu          – back to the channel list
//

import KSPlayer
import SwiftUI

struct PlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let lineup: [Channel]

    @State private var channel: Channel
    @State private var streamURL: URL?
    @State private var status: String = "Connecting…"
    @State private var isError = false
    @State private var showInfo = true
    @State private var nowPlaying: EPGProgram?
    @State private var upNext: EPGProgram?
    @State private var loadTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @FocusState private var isFocused: Bool

    init(initialChannel: Channel, lineup: [Channel]) {
        self.lineup = lineup
        _channel = State(initialValue: initialChannel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let streamURL {
                KSVideoPlayer(coordinator: coordinator, url: streamURL, options: playerOptions)
                    .onStateChanged { _, state in
                        handle(state: state)
                    }
                    .onFinish { _, error in
                        if let error {
                            status = "Playback stopped: \(error.localizedDescription)"
                            isError = true
                            showInfo = true
                        }
                    }
                    .ignoresSafeArea()
            }

            // The focus holder: a transparent full-screen button that receives
            // the remote's commands without putting any focus effect on the video.
            Button {
                toggleInfo()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(InvisibleButtonStyle())
            .focused($isFocused)
            .ignoresSafeArea()
            .onMoveCommand(perform: handleMove)
            .onExitCommand {
                dismiss()
            }
            .onPlayPauseCommand {
                togglePause()
            }

            infoOverlay
                .allowsHitTesting(false)
        }
        .onAppear {
            isFocused = true
            load(channel)
        }
        .onDisappear {
            loadTask?.cancel()
            hideTask?.cancel()
        }
    }

    // MARK: - Overlay

    private var infoOverlay: some View {
        VStack {
            Spacer()
            if showInfo {
                HStack(alignment: .bottom, spacing: 32) {
                    ChannelLogo(channel: channel, size: 160)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            if channel.number > 0 {
                                Text("\(channel.number)")
                                    .font(.title2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(channel.name)
                                .font(.title.bold())
                                .lineLimit(1)
                            if store.isFavorite(channel) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                        }
                        if let genre = store.genreTitle(for: channel) {
                            Text(genre)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let nowPlaying {
                            Text("Now: \(nowPlaying.name)  ·  \(timeRange(nowPlaying))")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        if let upNext {
                            Text("Next: \(upNext.name)  ·  \(timeRange(upNext))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 12) {
                            if isError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            }
                            Text(status)
                                .font(.callout)
                                .foregroundStyle(isError ? .yellow : .secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("▲ ▼ change channel")
                        Text("Menu to go back")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: showInfo)
    }

    private func timeRange(_ program: EPGProgram) -> String {
        let formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(program.start.formatted(formatter))–\(program.end.formatted(formatter))"
    }

    // MARK: - Playback

    private var playerOptions: KSOptions {
        let options = KSOptions()
        options.userAgent = StalkerClient.userAgent
        return options
    }

    private func load(_ target: Channel) {
        loadTask?.cancel()
        channel = target
        streamURL = nil
        nowPlaying = nil
        upNext = nil
        isError = false
        status = "Connecting…"
        showInfo = true
        hideTask?.cancel()
        loadTask = Task {
            do {
                let url = try await store.streamURL(for: target)
                guard !Task.isCancelled else { return }
                streamURL = url
                status = "Buffering…"
            } catch {
                guard !Task.isCancelled else { return }
                status = error.localizedDescription
                isError = true
                return
            }
            let programs = await store.shortEPG(for: target)
            guard !Task.isCancelled else { return }
            let now = Date()
            nowPlaying = programs.first { $0.isAiring(at: now) }
            upNext = programs.first { $0.start > now }
        }
    }

    private func handle(state: KSPlayerState) {
        switch state {
        case .initialized, .preparing:
            status = "Connecting…"
        case .readyToPlay:
            status = "Starting…"
        case .buffering:
            status = "Buffering…"
        case .bufferFinished:
            status = "Playing"
            isError = false
            scheduleHide()
        case .paused:
            status = "Paused"
            showInfo = true
        case .playedToTheEnd:
            status = "Stream ended"
            showInfo = true
        case .error:
            status = "The stream couldn't be played. Press ▲ or ▼ to try another channel, or select to retry."
            isError = true
            showInfo = true
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            step(by: -1)
        case .down:
            step(by: 1)
        case .left, .right:
            showInfo = true
            scheduleHide()
        @unknown default:
            break
        }
    }

    private func step(by offset: Int) {
        guard !lineup.isEmpty else { return }
        let index = lineup.firstIndex(of: channel) ?? 0
        let next = (index + offset + lineup.count) % lineup.count
        load(lineup[next])
    }

    private func toggleInfo() {
        if isError {
            load(channel)
            return
        }
        showInfo.toggle()
        if showInfo {
            scheduleHide()
        }
    }

    private func togglePause() {
        guard let layer = coordinator.playerLayer else { return }
        if coordinator.state.isPlaying {
            layer.pause()
        } else {
            layer.play()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, !isError else { return }
            showInfo = false
        }
    }
}

/// A button style with no focus or press effect, for the invisible
/// full-screen focus holder over the video.
struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
