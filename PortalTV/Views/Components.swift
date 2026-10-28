//
//  Components.swift
//  PortalTV
//
//  Small reusable pieces: the channel card and the logo image.
//

import SwiftUI

struct ChannelLogo: View {
    let channel: Channel
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let logo = channel.logo, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size * 0.75)
    }

    private var placeholder: some View {
        Text(initials)
            .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private var initials: String {
        let words = channel.name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "TV" : letters.joined()
    }
}

struct ChannelCard: View {
    let channel: Channel
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ChannelLogo(channel: channel, size: 150)
                Spacer()
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.title3)
                }
            }
            Text(channel.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(channel.number > 0 ? "Channel \(channel.number)" : " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 320, height: 240, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
