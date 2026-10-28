//
//  Models.swift
//  PortalTV
//
//  Plain value types the app stores and displays. Decoding of the portal's
//  loosely-typed JSON happens in StalkerDTOs.swift; these are the clean
//  results of that.
//

import Foundation

/// The one thing the portal authenticates: where it is and which MAC it knows.
struct PortalProfile: Codable, Equatable {
    var portalURL: String
    var macAddress: String

    var isComplete: Bool {
        !portalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && StalkerMAC.isValid(macAddress)
    }
}

/// A live-TV genre from `itv get_genres`.
struct Genre: Codable, Identifiable, Hashable {
    let id: String
    let title: String
}

/// A live channel from `itv get_all_channels`. `cmd` is the deferred play
/// command the portal resolves into a short-lived URL at play time.
struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let number: Int
    let cmd: String
    let logo: String?
    let genreId: String?
    let xmltvId: String?
}

/// One programme from the channel's short EPG.
struct EPGProgram: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let start: Date
    let end: Date

    func isAiring(at date: Date = Date()) -> Bool {
        start <= date && date < end
    }
}

/// What the portal told us about the account during the connection test.
struct AccountInfo: Equatable {
    let status: String?
    let expiryDate: String?
    let blockMessage: String?
}

/// Helpers for the MAC address a Stalker portal authenticates against.
enum StalkerMAC {
    /// The MAG vendor prefix most providers expect; the last three octets
    /// identify the (virtual) box and are what the subscription is bound to.
    static let prefix = "00:1A:79"

    static func generate() -> String {
        let octets = (0 ..< 3).map { _ in String(format: "%02X", UInt8.random(in: 0 ... 255)) }
        return "\(prefix):\(octets.joined(separator: ":"))"
    }

    static func isValid(_ mac: String) -> Bool {
        let pattern = "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
        return mac.range(of: pattern, options: .regularExpression) != nil
    }

    /// Accepts `001a79aabbcc`, `00-1a-79-aa-bb-cc` or `00:1a:79:aa:bb:cc` and
    /// returns the canonical upper-case colon form, or nil if it isn't a MAC.
    static func normalize(_ raw: String) -> String? {
        let hex = raw.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard hex.count == 12 else { return nil }
        var parts: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            parts.append(String(hex[index ..< next]))
            index = next
        }
        return parts.joined(separator: ":")
    }
}
