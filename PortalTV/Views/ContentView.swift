//
//  ContentView.swift
//  PortalTV
//
//  Routes between first-run setup and the channel browser.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.isConfigured {
                ChannelsView()
            } else {
                SetupView(isFirstRun: true)
            }
        }
        .task {
            await store.bootstrap()
        }
    }
}
