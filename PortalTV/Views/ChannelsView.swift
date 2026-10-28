//
//  ChannelsView.swift
//  PortalTV
//
//  The main screen: genres down the left, a grid of channels on the right.
//  Selecting a channel opens the full-screen player; a long press on a card
//  toggles it as a favorite.
//

import SwiftUI

struct ChannelsView: View {
    @Environment(AppStore.self) private var store

    enum ChannelFilter: Hashable {
        case all
        case favorites
        case genre(Genre)
    }

    @State private var filter: ChannelFilter = .all
    @State private var searchText = ""
    @State private var playing: Channel?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                    .frame(width: 420)
                    .padding(.trailing, 24)
                content
            }
            .padding(.horizontal, 40)
            .searchable(text: $searchText, prompt: "Channel name")
            .navigationTitle(sectionTitle)
        }
        .fullScreenCover(item: $playing) { channel in
            PlayerView(initialChannel: channel, lineup: visibleChannels)
                .environment(store)
        }
        .fullScreenCover(isPresented: $showSettings) {
            SetupView(isFirstRun: false)
                .environment(store)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Button {
                filter = .all
            } label: {
                sectionRow("All channels", count: store.channels.count, systemImage: "tv")
            }
            Button {
                filter = .favorites
            } label: {
                sectionRow("Favorites", count: store.favoriteChannels.count, systemImage: "heart.fill")
            }
            if let last = store.lastChannel {
                Button {
                    playing = last
                } label: {
                    Label("Resume \(last.name)", systemImage: "play.circle")
                        .lineLimit(1)
                }
            }

            if !store.genres.isEmpty {
                Text("Genres")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                ForEach(store.genres) { genre in
                    Button {
                        filter = .genre(genre)
                    } label: {
                        sectionRow(genre.title, count: store.channels(in: genre).count, systemImage: nil)
                    }
                }
            }

            Text("Portal")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
            Button {
                Task { await store.refreshChannels() }
            } label: {
                Label(store.phase == .loadingChannels ? "Reloading…" : "Reload channels", systemImage: "arrow.clockwise")
            }
            .disabled(store.phase == .loadingChannels)
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Text(sourceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listStyle(.plain)
    }

    private func sectionRow(_ title: String, count: Int, systemImage: String?) -> some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .connecting where store.channels.isEmpty, .loadingChannels where store.channels.isEmpty:
            placeholder(systemImage: "antenna.radiowaves.left.and.right", title: "Loading channels…", detail: "Fetching the lineup from the portal.")
        case let .failed(reason) where store.channels.isEmpty:
            placeholder(systemImage: "exclamationmark.triangle", title: "Couldn't load channels", detail: reason)
        default:
            if visibleChannels.isEmpty {
                placeholder(
                    systemImage: filter == .favorites ? "heart" : "magnifyingglass",
                    title: filter == .favorites ? "No favorites yet" : "No channels here",
                    detail: filter == .favorites ? "Long-press a channel to add it." : "Try another genre or search term."
                )
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 320), spacing: 40)], spacing: 48) {
                ForEach(visibleChannels) { channel in
                    Button {
                        playing = channel
                    } label: {
                        ChannelCard(channel: channel, isFavorite: store.isFavorite(channel))
                    }
                    .buttonStyle(.card)
                    .contextMenu {
                        Button(store.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites") {
                            store.toggleFavorite(channel)
                        }
                    }
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
        }
    }

    private func placeholder(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived

    private var sectionChannels: [Channel] {
        switch filter {
        case .all:
            return store.channels
        case .favorites:
            return store.favoriteChannels
        case let .genre(genre):
            return store.channels(in: genre)
        }
    }

    private var visibleChannels: [Channel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sectionChannels }
        return sectionChannels.filter {
            $0.name.localizedCaseInsensitiveContains(query) || String($0.number) == query
        }
    }

    private var sectionTitle: String {
        switch filter {
        case .all:
            return "All channels"
        case .favorites:
            return "Favorites"
        case let .genre(genre):
            return genre.title
        }
    }

    private var sourceDescription: String {
        switch store.source {
        case .none:
            return "No channel list yet"
        case let .cache(date):
            return "Cached \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .portal(date):
            return "Updated \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}
