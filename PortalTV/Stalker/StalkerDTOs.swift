//
//  StalkerDTOs.swift
//  PortalTV
//
//  Wire types for the Stalker (Ministra) middleware. Portals are loose with
//  JSON types — numbers arrive as strings or ints, booleans as 0/1 or "0"/"1",
//  and fields appear or vanish between implementations — so every field is
//  optional and decoded through `LenientString`.
//

import Foundation

/// Accepts a string, number, bool or null and exposes it as an optional string.
struct LenientString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "1" : "0"
        } else {
            value = nil
        }
    }
}

extension Optional where Wrapped == LenientString {
    /// The trimmed string, or nil when absent or empty.
    var text: String? {
        guard let raw = self?.value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var int: Int? {
        guard let text else { return nil }
        if let int = Int(text) { return int }
        if let double = Double(text) { return Int(double) }
        return nil
    }
}

/// Every middleware answer is `{"js": …}`.
struct StalkerEnvelope<T: Decodable>: Decodable {
    let js: T
}

/// A paged list: `{"data": [...], "total_items": "123", "max_page_items": "14"}`.
struct StalkerPage<Item: Decodable>: Decodable {
    let data: [Item]
    let totalItems: LenientString?
    let maxPageItems: LenientString?

    enum CodingKeys: String, CodingKey {
        case data
        case totalItems = "total_items"
        case maxPageItems = "max_page_items"
    }
}

/// `get_all_channels` answers with a page on most portals and a bare array on
/// a few; this accepts both.
struct StalkerChannelList: Decodable {
    let items: [StalkerChannelDTO]

    init(from decoder: Decoder) throws {
        if let page = try? StalkerPage<StalkerChannelDTO>(from: decoder) {
            items = page.data
        } else {
            let container = try decoder.singleValueContainer()
            items = try container.decode([StalkerChannelDTO].self)
        }
    }
}

struct StalkerHandshakeDTO: Decodable {
    let token: LenientString?
}

struct StalkerProfileDTO: Decodable {
    let id: LenientString?
    let status: LenientString?
    let expDate: LenientString?
    let msg: LenientString?
    let blockMsg: LenientString?

    enum CodingKeys: String, CodingKey {
        case id, status, msg
        case expDate = "exp_date"
        case blockMsg = "block_msg"
    }

    /// `msg` and `block_msg` joined, with the portal's HTML flattened. Ministra
    /// refuses an unknown device with a normal-looking profile such as
    /// `{"status":1,"msg":"Device conflict","block_msg":"Please contact your provider"}`
    /// and then answers every later call with a bare `Authorization failed.`.
    var blockMessage: String? {
        let parts = [msg.text, blockMsg.text].compactMap { $0 }.map(Self.plainText).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    /// A non-zero status alone isn't enough — portals are loose with it — so
    /// this also needs the message a genuine refusal carries.
    var isBlocked: Bool {
        blockMessage != nil && (status.text ?? "0") != "0"
    }

    var accountInfo: AccountInfo {
        AccountInfo(status: status.text, expiryDate: expDate.text, blockMessage: blockMessage)
    }

    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StalkerGenreDTO: Decodable {
    let id: LenientString?
    let title: LenientString?
}

struct StalkerChannelDTO: Decodable {
    let id: LenientString?
    let name: LenientString?
    let number: LenientString?
    let cmd: LenientString?
    let logo: LenientString?
    let tvGenreId: LenientString?
    let xmltvId: LenientString?

    enum CodingKeys: String, CodingKey {
        case id, name, number, cmd, logo
        case tvGenreId = "tv_genre_id"
        case xmltvId = "xmltv_id"
    }
}

struct StalkerCreateLinkDTO: Decodable {
    let cmd: LenientString?
}

struct StalkerEPGDTO: Decodable {
    let id: LenientString?
    let name: LenientString?
    let descr: LenientString?
    let time: LenientString?
    let timeTo: LenientString?
    let startTimestamp: LenientString?
    let stopTimestamp: LenientString?

    enum CodingKeys: String, CodingKey {
        case id, name, descr, time
        case timeTo = "time_to"
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
    }
}
