//
//  Persistence.swift
//  PortalTV
//
//  tvOS keeps app storage small: UserDefaults (under 500 KB) persists, while
//  the Caches folder can be purged by the system. So the portal profile,
//  favorites and last channel live in UserDefaults, and the channel list —
//  which can be thousands of entries — is only cached in Caches and refetched
//  from the portal whenever it's missing.
//

import Foundation
import OSLog

enum Persistence {
    private static let log = Logger(subsystem: "PortalTV", category: "Persistence")
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let profile = "portal.profile"
        static let favorites = "channels.favorites"
        static let lastChannel = "channels.last"
    }

    // MARK: Profile

    static func loadProfile() -> PortalProfile? {
        guard let data = defaults.data(forKey: Key.profile) else { return nil }
        return try? JSONDecoder().decode(PortalProfile.self, from: data)
    }

    static func save(profile: PortalProfile?) {
        guard let profile, let data = try? JSONEncoder().encode(profile) else {
            defaults.removeObject(forKey: Key.profile)
            return
        }
        defaults.set(data, forKey: Key.profile)
    }

    // MARK: Favorites / last channel

    static func loadFavorites() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.favorites) ?? [])
    }

    static func save(favorites: Set<String>) {
        defaults.set(Array(favorites).sorted(), forKey: Key.favorites)
    }

    static func loadLastChannelId() -> String? {
        defaults.string(forKey: Key.lastChannel)
    }

    static func save(lastChannelId: String?) {
        if let lastChannelId {
            defaults.set(lastChannelId, forKey: Key.lastChannel)
        } else {
            defaults.removeObject(forKey: Key.lastChannel)
        }
    }

    // MARK: Channel cache (purgeable)

    private struct ChannelCache: Codable {
        let portalURL: String
        let macAddress: String
        let fetchedAt: Date
        let genres: [Genre]
        let channels: [Channel]
    }

    private static var cacheURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("PortalTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("channels.json")
    }

    /// The cached lineup for this exact portal + MAC, if there is one.
    static func loadChannelCache(for profile: PortalProfile) -> (genres: [Genre], channels: [Channel], fetchedAt: Date)? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ChannelCache.self, from: data),
              cache.portalURL == profile.portalURL,
              cache.macAddress == profile.macAddress
        else { return nil }
        return (cache.genres, cache.channels, cache.fetchedAt)
    }

    static func saveChannelCache(for profile: PortalProfile, genres: [Genre], channels: [Channel]) {
        guard let url = cacheURL else { return }
        let cache = ChannelCache(
            portalURL: profile.portalURL,
            macAddress: profile.macAddress,
            fetchedAt: Date(),
            genres: genres,
            channels: channels
        )
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't write channel cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clearChannelCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
