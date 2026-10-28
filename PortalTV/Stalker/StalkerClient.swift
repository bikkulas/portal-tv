//
//  StalkerClient.swift
//  PortalTV
//
//  Talks to a Stalker (Ministra) portal the way a MAG set-top box does:
//  handshake → bearer token → profile, then the live-TV catalog, and a fresh
//  short-lived stream URL from `create_link` every time a channel is played.
//
//  Portal quirks this handles:
//  - The middleware lives at /portal.php, /server/load.php or
//    /stalker_portal/server/load.php depending on the installation; the
//    handshake probes each and pins the one that answers JSON.
//  - Portals gate the middleware behind the MAG User-Agent and expect the MAC
//    in a cookie; a generic client gets an HTML page instead of JSON.
//  - Tokens expire. A small "Authorization failed." body means re-handshake
//    once and retry.
//  - `create_link` answers with `ffmpeg http://…` (sometimes `auto …`); the
//    playable URL is the first http(s) token.
//

import Foundation
import OSLog

enum StalkerError: LocalizedError {
    case invalidURL
    case handshakeFailed(String)
    case authorizationFailed
    case deviceBlocked(String)
    case noStreamURL
    case httpStatus(Int)
    case notJSON(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The portal URL is not a valid address."
        case let .handshakeFailed(detail):
            return "Couldn't connect to the portal. Check the portal URL and MAC address. (\(detail))"
        case .authorizationFailed:
            return "The portal rejected this MAC address. It may not be registered, or the subscription has expired."
        case let .deviceBlocked(message):
            return "The portal blocked this device: \(message)"
        case .noStreamURL:
            return "The portal didn't return a stream address for this channel."
        case let .httpStatus(code):
            return "The portal answered with HTTP \(code)."
        case let .notJSON(detail):
            return "The portal answered with something other than JSON (\(detail))."
        case let .network(error):
            return error.localizedDescription
        }
    }

    var isAuthFailure: Bool {
        if case .authorizationFailed = self { return true }
        return false
    }
}

actor StalkerClient {
    /// The MAG250 user agent portals expect on middleware and stream requests.
    static let userAgent = "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Std Beta. Lib: 2.6.16-15"

    private struct Session {
        let endpoint: URL
        let token: String
    }

    let profile: PortalProfile
    private let urlSession: URLSession
    private var session: Session?
    private let log = Logger(subsystem: "PortalTV", category: "Stalker")

    init(profile: PortalProfile) {
        self.profile = profile
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 90
        config.httpAdditionalHeaders = ["Accept": "*/*"]
        urlSession = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Handshakes and reads the profile. Used as the connection test when the
    /// user saves portal settings.
    func connect() async throws -> AccountInfo {
        let session = try await ensureSession(forceRefresh: true)
        let dto = try await getProfile(using: session)
        if dto.isBlocked, let message = dto.blockMessage {
            throw StalkerError.deviceBlocked(message)
        }
        return dto.accountInfo
    }

    func genres() async throws -> [Genre] {
        let envelope: StalkerEnvelope<[StalkerGenreDTO]> = try await request(type: "itv", action: "get_genres")
        return envelope.js.compactMap { dto in
            guard let id = dto.id.text, id != "*", let title = dto.title.text else { return nil }
            return Genre(id: id, title: title)
        }
    }

    func allChannels() async throws -> [Channel] {
        let envelope: StalkerEnvelope<StalkerChannelList> = try await request(type: "itv", action: "get_all_channels")
        var seen = Set<String>()
        var channels: [Channel] = []
        for dto in envelope.js.items {
            guard let id = dto.id.text, let cmd = dto.cmd.text, !seen.contains(id) else { continue }
            seen.insert(id)
            channels.append(Channel(
                id: id,
                name: dto.name.text ?? "Channel \(id)",
                number: dto.number.int ?? 0,
                cmd: cmd,
                logo: Self.logoURL(from: dto.logo.text, portal: profile.portalURL),
                genreId: dto.tvGenreId.text,
                xmltvId: dto.xmltvId.text
            ))
        }
        return channels.sorted { lhs, rhs in
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Resolves the channel's `cmd` into a playable URL. Links are short-lived
    /// and often single-use, so this is called every time playback starts.
    func streamURL(for channel: Channel) async throws -> URL {
        var extra = [URLQueryItem(name: "cmd", value: channel.cmd)]
        extra += Self.forwardedQueryItems(from: channel.cmd)
        extra += [
            URLQueryItem(name: "series", value: ""),
            URLQueryItem(name: "forced_storage", value: ""),
            URLQueryItem(name: "disable_ad", value: "0"),
            URLQueryItem(name: "download", value: "0"),
            URLQueryItem(name: "force_ch_link_check", value: "0")
        ]
        let envelope: StalkerEnvelope<StalkerCreateLinkDTO> = try await request(type: "itv", action: "create_link", extra: extra)
        guard let raw = envelope.js.cmd.text, let url = Self.playableURL(from: raw) else {
            throw StalkerError.noStreamURL
        }
        // An empty `stream=` means the portal minted a link without a channel
        // id (Xtream-UI emulations do this when the forwarded params are
        // missing) — it would only 405.
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let stream = components.queryItems?.first(where: { $0.name == "stream" }),
           (stream.value ?? "").isEmpty
        {
            throw StalkerError.noStreamURL
        }
        return url
    }

    /// Now/next programmes for a channel. Best effort: many portals have no EPG.
    func shortEPG(channelId: String) async throws -> [EPGProgram] {
        let envelope: StalkerEnvelope<[StalkerEPGDTO]> = try await request(
            type: "itv",
            action: "get_short_epg",
            extra: [URLQueryItem(name: "ch_id", value: channelId), URLQueryItem(name: "size", value: "10")]
        )
        return envelope.js.compactMap { dto in
            guard let name = dto.name.text,
                  let start = Self.date(timestamp: dto.startTimestamp.text, fallback: dto.time.text),
                  let end = Self.date(timestamp: dto.stopTimestamp.text, fallback: dto.timeTo.text)
            else { return nil }
            return EPGProgram(
                id: dto.id.text ?? "\(channelId)-\(Int(start.timeIntervalSince1970))",
                name: name,
                description: dto.descr.text,
                start: start,
                end: end
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: - Session

    private func ensureSession(forceRefresh: Bool = false) async throws -> Session {
        if !forceRefresh, let session {
            return session
        }
        session = nil
        let fresh = try await handshake()
        session = fresh
        return fresh
    }

    /// Tries each candidate endpoint until one hands out a token, then primes
    /// the session with `get_profile` (some portals only activate the token
    /// after the profile call).
    private func handshake() async throws -> Session {
        let endpoints = Self.candidateEndpoints(for: profile.portalURL)
        guard !endpoints.isEmpty else { throw StalkerError.invalidURL }

        var failures: [String] = []
        for endpoint in endpoints {
            try Task.checkCancellation()
            let url = Self.appendingQuery(to: endpoint, [
                ("type", "stb"),
                ("action", "handshake"),
                ("token", ""),
                ("JsHttpRequest", "1-xml")
            ])
            do {
                let envelope: StalkerEnvelope<StalkerHandshakeDTO> = try await perform(url: url, token: nil)
                guard let token = envelope.js.token.text else {
                    failures.append("\(endpoint.path): no token")
                    continue
                }
                let session = Session(endpoint: endpoint, token: token)
                log.info("Handshake OK via \(endpoint.path, privacy: .public)")
                _ = try? await getProfile(using: session)
                return session
            } catch {
                failures.append("\(endpoint.path): \(error.localizedDescription)")
                log.info("Handshake candidate \(endpoint.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        throw StalkerError.handshakeFailed(failures.joined(separator: "; "))
    }

    private func getProfile(using session: Session) async throws -> StalkerProfileDTO {
        let url = Self.appendingQuery(to: session.endpoint, [
            ("type", "stb"),
            ("action", "get_profile"),
            ("hd", "1"),
            ("stb_type", "MAG250"),
            ("client_type", "STB"),
            ("JsHttpRequest", "1-xml")
        ])
        let envelope: StalkerEnvelope<StalkerProfileDTO> = try await perform(url: url, token: session.token)
        return envelope.js
    }

    // MARK: - Requests

    /// An authorized middleware call. Re-handshakes once on an expired token
    /// and retries transient network failures with a short backoff.
    private func request<T: Decodable>(type: String, action: String, extra: [URLQueryItem] = []) async throws -> T {
        var refreshedAuth = false
        var attempt = 0
        while true {
            attempt += 1
            let session = try await ensureSession(forceRefresh: refreshedAuth)
            var pairs: [(String, String)] = [("type", type), ("action", action)]
            pairs += extra.map { ($0.name, $0.value ?? "") }
            pairs.append(("JsHttpRequest", "1-xml"))
            let url = Self.appendingQuery(to: session.endpoint, pairs)
            do {
                return try await perform(url: url, token: session.token)
            } catch let error as StalkerError {
                if error.isAuthFailure, !refreshedAuth {
                    refreshedAuth = true
                    log.info("Token rejected; re-handshaking")
                    continue
                }
                guard case .network = error, attempt < 3 else {
                    log.error("\(type, privacy: .public) \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
    }

    /// One HTTP round trip with the headers a portal expects.
    private func perform<T: Decodable>(url: URL, token: String?) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("Model: MAG250; Link: WiFi", forHTTPHeaderField: "X-User-Agent")
        urlRequest.setValue(Self.referer(for: url), forHTTPHeaderField: "Referer")
        urlRequest.setValue(
            "mac=\(profile.macAddress); stb_lang=en; timezone=\(TimeZone.current.identifier)",
            forHTTPHeaderField: "Cookie"
        )
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw StalkerError.network(error)
        }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw StalkerError.authorizationFailed
            }
            throw StalkerError.httpStatus(http.statusCode)
        }
        if Self.isAuthorizationFailure(data) {
            throw StalkerError.authorizationFailed
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw StalkerError.notJSON(Self.fingerprint(data))
        }
    }

    // MARK: - Helpers

    /// Middleware endpoints to try, derived from whatever the user pasted
    /// (`http://host/c/`, `http://host:8080/stalker_portal/c/`, a bare host…).
    static func candidateEndpoints(for portalURL: String) -> [URL] {
        var raw = portalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http://"), !raw.lowercased().hasPrefix("https://") {
            raw = "http://" + raw
        }
        guard var components = URLComponents(string: raw), let host = components.host, !host.isEmpty else { return [] }
        let pastedPath = components.path.lowercased()
        components.query = nil
        components.fragment = nil

        let paths: [String]
        if pastedPath.contains("stalker_portal") {
            paths = ["/stalker_portal/server/load.php", "/portal.php", "/server/load.php"]
        } else {
            paths = ["/portal.php", "/server/load.php", "/stalker_portal/server/load.php"]
        }
        return paths.compactMap { path in
            var copy = components
            copy.path = path
            return copy.url
        }
    }

    /// The portal's `/c/` page on the host being called — what a real box sends.
    private static func referer(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.path = components.path.contains("/stalker_portal/") ? "/stalker_portal/c/" : "/c/"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    /// Builds the query by hand so that `+`, `&`, `=` and `/` inside values are
    /// escaped — URLComponents leaves `+` alone and PHP would read it as a space.
    static func appendingQuery(to endpoint: URL, _ pairs: [(String, String)]) -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return endpoint }
        let encoded = pairs.map { "\(strictEncode($0.0))=\(strictEncode($0.1))" }.joined(separator: "&")
        if let existing = components.percentEncodedQuery, !existing.isEmpty {
            components.percentEncodedQuery = existing + "&" + encoded
        } else {
            components.percentEncodedQuery = encoded
        }
        return components.url ?? endpoint
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func strictEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Query parameters embedded in a direct-URL `cmd`, re-sent as top-level
    /// `create_link` parameters. Xtream-UI-style emulations hand out cmds that
    /// are full stream URLs and read `stream` / `extension` from the request's
    /// own query rather than from `cmd`. Genuine Ministra ignores the extras.
    /// `mac` and `play_token` stay out — the portal mints fresh ones.
    static func forwardedQueryItems(from cmd: String) -> [URLQueryItem] {
        guard let url = playableURL(from: cmd),
              url.scheme == "http" || url.scheme == "https",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [] }
        let excluded: Set<String> = ["mac", "play_token", "token", "type", "action", "cmd", "JsHttpRequest"]
        return items.filter { !excluded.contains($0.name) }
    }

    /// Extracts the URL from a `cmd` such as `ffmpeg http://host/ch/1 extra`.
    static func playableURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "https?://", options: .regularExpression) else {
            return URL(string: trimmed)
        }
        let fromScheme = trimmed[range.lowerBound...]
        let urlPart = fromScheme.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? String(fromScheme)
        return URL(string: urlPart)
    }

    /// Channel logos arrive as absolute URLs or as bare filenames that live
    /// under the portal's `misc/logos` folder.
    static func logoURL(from logo: String?, portal: String) -> String? {
        guard let logo, !logo.isEmpty else { return nil }
        if logo.lowercased().hasPrefix("http://") || logo.lowercased().hasPrefix("https://") {
            return logo
        }
        guard let base = candidateEndpoints(for: portal).first,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.query = nil
        if logo.hasPrefix("/") {
            components.path = logo
        } else {
            components.path = "/stalker_portal/misc/logos/320/" + logo
        }
        return components.url?.absoluteString
    }

    private static func isAuthorizationFailure(_ data: Data) -> Bool {
        guard data.count < 256, let body = String(data: data, encoding: .utf8) else { return false }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveContains("authorization failed")
    }

    private static func fingerprint(_ data: Data) -> String {
        guard let body = String(data: data.prefix(120), encoding: .utf8) else {
            return "\(data.count) bytes of binary"
        }
        let flattened = body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.isEmpty { return "empty body" }
        return flattened.lowercased().hasPrefix("<") ? "HTML page: \(flattened.prefix(60))…" : "\(flattened.prefix(80))…"
    }

    private static let portalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func date(timestamp: String?, fallback: String?) -> Date? {
        if let timestamp, let seconds = TimeInterval(timestamp), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        if let fallback {
            return portalDateFormatter.date(from: fallback)
        }
        return nil
    }
}
