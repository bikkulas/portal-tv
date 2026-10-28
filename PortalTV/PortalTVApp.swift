//
//  PortalTVApp.swift
//  PortalTV
//
//  A personal Apple TV player for Stalker/MAC-portal IPTV subscriptions.
//

import KSPlayer
import SwiftUI

@main
struct PortalTVApp: App {
    @State private var store = AppStore()

    init() {
        // Most IPTV live streams are raw MPEG-TS over HTTP, which AVPlayer can't
        // open, so the FFmpeg-based engine goes first and AVPlayer is the
        // fallback (it handles HLS streams more efficiently when they appear).
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSAVPlayer.self
        KSOptions.isAutoPlay = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
