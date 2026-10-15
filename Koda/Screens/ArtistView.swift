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
    /// One line of the audience text at the current text size.
    @ScaledMetric(relativeTo: .subheadline) private var audienceLineHeight: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                AsyncContent(state: state, retry: load, placeholder: .placeholder(summary)) { page in
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
        .revealsTitle(state.value?.artist.name ?? summary.name, after: 340)
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
                ArtistHeroImage(artwork: banner, preview: summary.artwork, tint: palette.palette.mesh[4],
                                width: width, height: heroHeight + pull)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    let name = state.value?.artist.name ?? summary.name
                    if name.isEmpty {
                        // Opened from a link, the name comes with the page.
                        Capsule().fill(.white.opacity(0.25)).frame(width: 180, height: 34)
                            .shimmer()
                    } else {
                        Text(name)
                            .font(.system(size: 40, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .transition(.opacity)
                    }
                    // A slot one line tall, always there, so the name sits in the same place
                    // before the audience line arrives, after it, and for artists without one.
                    ZStack(alignment: .leading) {
                        if let audience = state.value?.artist.subtitle {
                            Text(audience)
                                .font(.subheadline.weight(.medium))
                                .opacity(0.85)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: audienceLineHeight, alignment: .leading)
                    .animation(.easeOut(duration: 0.25), value: state.value?.artist.subtitle)
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
/// The artist's banner, loaded progressively: the small photo already on screen elsewhere
/// shows at once, blurred and enlarged, and the sharp banner fades in over it.
private struct ArtistHeroImage: View {
    let artwork: Artwork?
    /// The small photo from the list the artist was opened from, likely cached already.
    let preview: Artwork?
    /// The photo's main colour, for the space while nothing has loaded.
    let tint: Color
    let width: CGFloat
    let height: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var previewImage: UIImage?

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
            LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            if let previewImage, image == nil {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .scaleEffect(1.2)
                    .transition(.opacity)
            }
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .shimmer(image == nil && previewImage == nil)
        .clipped()
        .task(id: preview?.url) {
            guard let url = preview?.url(pixels: 120), image == nil else { return }
            var small = ImagePipeline.shared.cached(url, pixels: 120)
            if small == nil { small = await ImagePipeline.shared.image(url, pixels: 120) }
            guard image == nil else { return }
            withAnimation(.easeOut(duration: 0.2)) { previewImage = small }
        }
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
