//
//  AppStore.swift
//  PortalTV
//
//  The app's single source of truth: the portal profile, the channel lineup,
//  favorites and the last channel watched. Views read it through the SwiftUI
//  environment; all mutation goes through the methods below.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppStore {
    enum Phase: Equatable {
        case idle
        case connecting
        case loadingChannels
        case ready
        case failed(String)
    }

    /// Where channels came from, shown in the UI so a stale cache is obvious.
    enum Source: Equatable {
        case none
        case cache(Date)
        case portal(Date)
    }

    private(set) var profile: PortalProfile?
    private(set) var genres: [Genre] = []
    private(set) var channels: [Channel] = []
    private(set) var favorites: Set<String> = []
    private(set) var lastChannelId: String?
    private(set) var accountInfo: AccountInfo?
    private(set) var phase: Phase = .idle
    private(set) var source: Source = .none

    private var client: StalkerClient?
    private let log = Logger(subsystem: "PortalTV", category: "Store")

    init() {
        profile = Persistence.loadProfile()
        favorites = Persistence.loadFavorites()
        lastChannelId = Persistence.loadLastChannelId()
        if let profile {
            client = StalkerClient(profile: profile)
        }
    }

    var isConfigured: Bool { profile != nil }

    var lastChannel: Channel? {
        guard let lastChannelId else { return nil }
        return channels.first { $0.id == lastChannelId }
    }

    var favoriteChannels: [Channel] {
        channels.filter { favorites.contains($0.id) }
    }

    func channels(in genre: Genre?) -> [Channel] {
        guard let genre else { return channels }
        return channels.filter { $0.genreId == genre.id }
    }

    func genreTitle(for channel: Channel) -> String? {
        guard let genreId = channel.genreId else { return nil }
        return genres.first { $0.id == genreId }?.title
    }

    // MARK: - Lifecycle

    /// On launch: show the cached lineup immediately, then refresh from the
    /// portal in the background.
    func bootstrap() async {
        guard let profile, let client else { return }
        if let cached = Persistence.loadChannelCache(for: profile) {
            genres = cached.genres
            channels = cached.channels
            source = .cache(cached.fetchedAt)
            phase = .ready
        }
        await refreshChannels(using: client, profile: profile, showProgress: channels.isEmpty)
    }

    /// Connection test + save. Called from the setup screen.
    func connect(to newProfile: PortalProfile) async -> Bool {
        phase = .connecting
        let candidate = StalkerClient(profile: newProfile)
        do {
            let info = try await candidate.connect()
            accountInfo = info
        } catch {
            log.error("Connect failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
            return false
        }

        if newProfile != profile {
            Persistence.clearChannelCache()
            channels = []
            genres = []
            source = .none
        }
        profile = newProfile
        client = candidate
        Persistence.save(profile: newProfile)
        await refreshChannels(using: candidate, profile: newProfile, showProgress: true)
        if case .failed = phase {
            return false
        }
        return true
    }

    func refreshChannels() async {
        guard let profile, let client else { return }
        await refreshChannels(using: client, profile: profile, showProgress: true)
    }

    private func refreshChannels(using client: StalkerClient, profile: PortalProfile, showProgress: Bool) async {
        if showProgress {
            phase = .loadingChannels
        }
        do {
            async let fetchedGenres = client.genres()
            let fetchedChannels = try await client.allChannels()
            let resolvedGenres = (try? await fetchedGenres) ?? []
            channels = fetchedChannels
            genres = resolvedGenres
            source = .portal(Date())
            phase = .ready
            Persistence.saveChannelCache(for: profile, genres: resolvedGenres, channels: fetchedChannels)
            log.info("Loaded \(fetchedChannels.count) channels in \(resolvedGenres.count) genres")
        } catch {
            log.error("Channel refresh failed: \(error.localizedDescription, privacy: .public)")
            if channels.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                // Keep showing the cache; the failure is visible in `source`.
                phase = .ready
            }
        }
    }

    func disconnect() {
        profile = nil
        client = nil
        channels = []
        genres = []
        accountInfo = nil
        source = .none
        phase = .idle
        Persistence.save(profile: nil)
        Persistence.clearChannelCache()
    }

    // MARK: - Playback

    func streamURL(for channel: Channel) async throws -> URL {
        guard let client else { throw StalkerError.invalidURL }
        let url = try await client.streamURL(for: channel)
        lastChannelId = channel.id
        Persistence.save(lastChannelId: channel.id)
        return url
    }

    func shortEPG(for channel: Channel) async -> [EPGProgram] {
        guard let client else { return [] }
        return (try? await client.shortEPG(channelId: channel.id)) ?? []
    }

    // MARK: - Favorites

    func isFavorite(_ channel: Channel) -> Bool {
        favorites.contains(channel.id)
    }

    func toggleFavorite(_ channel: Channel) {
        if favorites.contains(channel.id) {
            favorites.remove(channel.id)
        } else {
            favorites.insert(channel.id)
        }
        Persistence.save(favorites: favorites)
    }
}
