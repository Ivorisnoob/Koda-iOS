import KodaCore
import SwiftUI

struct ArtistView: View {
    let summary: ArtistSummary

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var state: LoadState<ArtistPage> = .loading
    @State private var palette = PaletteModel()
    @State private var pull: CGFloat = 0
    @State private var aboutExpanded = false

    private let heroHeight: CGFloat = 400

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                AsyncContent(state: state, retry: load) { page in
                    content(page)
                }
            }
            .padding(.bottom, 32)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            pull = max(0, -offset)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let saved = library.isSaved(artist: summary.id)
                Button(saved ? "Remove from Library" : "Add to Library", systemImage: saved ? "checkmark" : "plus") {
                    library.toggleSave(state.value?.artist ?? summary)
                }
                .sensoryFeedback(.success, trigger: saved)
            }
        }
        .task { await palette.load(summary.artwork) }
        .task { if state.value == nil { await load() } }
    }

    /// The photo stretches with an overscroll instead of leaving a gap above it.
    private var hero: some View {
        let banner = state.value?.banner ?? summary.artwork
        return GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .bottomLeading) {
                ArtistHeroImage(artwork: banner, width: width, height: heroHeight + pull)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.value?.artist.name ?? summary.name)
                        .font(.system(size: 40, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if let audience = state.value?.artist.subtitle {
                        Text(audience).font(.subheadline.weight(.medium)).opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(width: width, height: heroHeight + pull)
            .offset(y: -pull)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private func content(_ page: ArtistPage) -> some View {
        PlayShuffleButtons(shuffleTitle: "Radio",
                           play: { if !page.topSongs.isEmpty { player.play(page.topSongs) } },
                           shuffle: { if let first = page.topSongs.first { player.startRadio(from: first) } })
            .padding(.horizontal, 20)

        if !page.topSongs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Top songs",
                              seeAll: page.allSongsPlaylistId.map { .playlist(PlaylistSummary(id: $0, title: "\(page.artist.name): Songs", artwork: page.banner)) })
                ForEach(Array(page.topSongs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song) { player.play(page.topSongs, startAt: index) }
                }
            }
            .padding(.horizontal, 20)
        }
        if !page.albums.isEmpty {
            ShelfView(title: "Albums") {
                ForEach(page.albums) { album in
                    NavigationLink(value: Route.album(album)) {
                        CoverCard(artwork: album.artwork, title: album.title, subtitle: album.year.map(String.init))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !page.singles.isEmpty {
            ShelfView(title: "Singles & EPs") {
                ForEach(page.singles) { single in
                    NavigationLink(value: Route.album(single)) {
                        CoverCard(artwork: single.artwork, title: single.title,
                                  subtitle: [single.kind?.rawValue, single.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !page.featuredOn.isEmpty {
            ShelfView(title: "Featured on") {
                ForEach(page.featuredOn) { playlist in
                    NavigationLink(value: Route.playlist(playlist)) {
                        CoverCard(artwork: playlist.artwork, title: playlist.title, subtitle: playlist.subtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !page.similar.isEmpty {
            ShelfView(title: "Fans also like") {
                ForEach(page.similar) { artist in
                    NavigationLink(value: Route.artist(artist)) { ArtistCard(artist: artist) }
                        .buttonStyle(.plain)
                }
            }
        }
        if let about = page.description {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").font(.title3.bold())
                Text(about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(aboutExpanded ? nil : 4)
                    .onTapGesture { withAnimation(.snappy) { aboutExpanded.toggle() } }
            }
            .padding(.horizontal, 20)
        }
    }

    private func load() async {
        state = .loading
        do {
            let page = try await app.music.artist(summary.id)
            state = .loaded(page)
            await palette.load(page.banner)
        } catch {
            state = .failed(error.friendlyMessage)
        }
    }
}

/// The artist photo cropped by Google to the hero's shape.
///
/// The immersive banner is served wide with the portrait pillarboxed inside;
/// its `-p` directive crops the full-resolution source to whatever box is
/// asked for, which is sharper than cropping the wide banner here.
private struct ArtistHeroImage: View {
    let artwork: Artwork?
    let width: CGFloat
    let height: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    private var url: URL? {
        guard let artwork else { return nil }
        let w = Int(width * scale), h = Int(400 * scale)
        let string = artwork.url.absoluteString
        guard string.contains("googleusercontent.com"), let separator = string.lastIndex(of: "=") else { return artwork.url }
        let directives = String(string[separator...]).replacingOccurrences(of: #"w\d+-h\d+"#, with: "w\(w)-h\(h)", options: .regularExpression)
        return URL(string: String(string[..<separator]) + directives)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: url) {
            guard let url else { return }
            let pixels = Int(max(width, 400) * scale)
            if let hit = ImagePipeline.shared.cached(url, pixels: pixels) {
                image = hit
                return
            }
            let loaded = await ImagePipeline.shared.image(url, pixels: pixels)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}
