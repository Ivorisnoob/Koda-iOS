import KodaCore
import SwiftUI

/// The top of an album or playlist page.
struct CollectionHeader: View {
    let artwork: Artwork?
    let title: String
    var byline: String?
    /// The artists behind the byline, to open from it.
    var bylineArtists: [ArtistRef] = []
    var openArtist: (ArtistSummary) -> Void = { _ in }
    var detail: String?
    var description: String?
    var accent: Color
    var shuffleTitle = "Shuffle"
    let play: () -> Void
    let shuffle: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 14) {
            ArtworkView(artwork: artwork, size: 248, cornerRadius: 14)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .padding(.bottom, 4)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let byline, !byline.isEmpty {
                    let opens = !ArtistRef.linked(bylineArtists).isEmpty
                    ArtistLinks(line: byline, artists: bylineArtists, open: openArtist) {
                        Text(byline).font(.title3).foregroundStyle(opens ? accent : .secondary).lineLimit(1)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            .padding(.horizontal, 24)
            PlayShuffleButtons(shuffleTitle: shuffleTitle, play: play, shuffle: shuffle)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .contentShape(.rect)
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
                    .accessibilityHint(expanded ? "Collapses the description" : "Shows the whole description")
            }
        }
        .padding(.top, 8)
    }
}

/// A wash of the cover's colour behind the top of a page, fading into the background.
struct ArtworkGlow: View {
    let palette: Palette

    var body: some View {
        LinearGradient(
            colors: [palette.mesh[1].opacity(0.55), palette.mesh[4].opacity(0.25), .clear],
            startPoint: .top, endPoint: .bottom)
            .frame(height: 520)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
