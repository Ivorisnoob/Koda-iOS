import KodaCore
import SwiftUI

@MainActor
@Observable
final class HomeModel {
    struct Content {
        var quickPicks: [Song] = []
        var quickPicksTitle = "Quick picks"
        var shelves: [Shelf] = []
        var newReleases: Shelf?
        var chartArtists: [ArtistSummary] = []
        var trending: [Song] = []
    }

    /// Songs woven from the radios of what the listener plays most.
    struct Mix: Equatable {
        var artists: [String]
        var songs: [Song]
        /// Built from listening; otherwise trending songs for someone new.
        var isPersonal: Bool
    }

    private(set) var state: LoadState<Content> = .loading
    private(set) var mix: Mix?
    private(set) var isMixing = false
    /// Portraits for the listener's top artists, by channel id; fetched after the page shows.
    private(set) var artistPhotos: [String: Artwork] = [:]

    func load(music: YouTubeMusic, library: Library) async {
        if state.value == nil { state = .loading }
        let recent = library.recent
        let taste = Taste(library: library)
        async let home = music.home()
        async let explore = try? music.explore()
        async let charts = try? music.charts()
        async let picks = quickPicks(music: music, recent: recent)
        do {
            let homePage = try await home
            var content = Content()
            content.shelves = homePage.shelves
            let explorePage = await explore
            content.newReleases = explorePage?.shelves.first { $0.title == "New albums & singles" }
            content.trending = trending(explorePage)
            content.chartArtists = (await charts)?.shelves.first { $0.title == "Top artists" }?.items.compactMap {
                if case .artist(let a) = $0 { return a }
                return nil
            } ?? []
            let (title, songs) = await picks
            content.quickPicksTitle = title
            content.quickPicks = songs.isEmpty ? content.trending : songs
            state = .loaded(content)
            if mix == nil, taste.isEmpty, !content.trending.isEmpty {
                mix = Mix(artists: Array(Set(content.trending.map(Taste.leadArtist))).sorted().prefix(3).map { $0 },
                          songs: content.trending, isPersonal: false)
            }
        } catch {
            if state.value == nil { state = .failed(error.friendlyMessage) }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.buildMix(music: music, taste: taste, recent: recent) }
            group.addTask { await self.loadArtistPhotos(music: music, library: library) }
        }
    }

    /// Your Mix: a radio from each top artist's favourite song, woven together.
    private func buildMix(music: YouTubeMusic, taste: Taste, recent: [Song]) async {
        guard !taste.isEmpty else { return }
        isMixing = true
        defer { isMixing = false }
        let radios = await withTaskGroup(of: (Int, [Song]).self) { group in
            for (index, seed) in taste.seeds.enumerated() {
                group.addTask { (index, (try? await music.radio(for: seed.id).songs) ?? []) }
            }
            var byIndex: [Int: [Song]] = [:]
            for await (index, songs) in group { byIndex[index] = songs }
            return taste.seeds.indices.map { byIndex[$0] ?? [] }
        }
        // The seeds and the last few songs played are left out, so the mix is something to go on to.
        let skip = Set(taste.seeds.map(\.id) + recent.prefix(10).map(\.id))
        let songs = Taste.weave(radios, excluding: skip)
        guard !songs.isEmpty else { return }
        withAnimation(.smooth) { mix = Mix(artists: Array(taste.artists.prefix(3)), songs: songs, isPersonal: true) }
    }

    private func loadArtistPhotos(music: YouTubeMusic, library: Library) async {
        let ids = topArtists(library).compactMap(\.id).filter { artistPhotos[$0] == nil }
        guard !ids.isEmpty else { return }
        let found = await withTaskGroup(of: (String, Artwork?).self) { group in
            for id in ids {
                group.addTask { (id, try? await music.artist(id).artist.artwork) }
            }
            var found: [String: Artwork] = [:]
            for await (id, artwork) in group { if let artwork { found[id] = artwork } }
            return found
        }
        artistPhotos.merge(found) { _, new in new }
    }

    /// The listener's most-played artists that can be opened, strongest first.
    func topArtists(_ library: Library, limit: Int = 10) -> [ArtistRef] {
        let taste = Taste(library: library, maxSeeds: 0)
        var refs: [String: ArtistRef] = [:]
        for stats in library.songStats.values {
            if let ref = stats.song.artists.first, ref.id != nil { refs[ref.name] = ref }
        }
        return taste.artists.compactMap { refs[$0] }.prefix(limit).map { $0 }
    }

    /// Songs like the last one played; with no history yet, nothing (trending fills in).
    private func quickPicks(music: YouTubeMusic, recent: [Song]) async -> (String, [Song]) {
        guard let seed = recent.first, let radio = try? await music.radio(for: seed.id) else { return ("Quick picks", []) }
        let songs = Array(radio.songs.filter { $0.id != seed.id }.prefix(20))
        return ("Quick picks", songs)
    }

    private func trending(_ explore: ShelfPage?) -> [Song] {
        explore?.shelves.first { $0.title == "Trending" }?.items.compactMap {
            if case .song(let s) = $0 { return s }
            return nil
        } ?? []
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var model = HomeModel()
    @State private var showsProfile = false

    var body: some View {
        ScrollView {
            Group {
                switch model.state {
                case .loading:
                    HomeSkeleton()
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.glass)
                    }
                    .frame(minHeight: 400)
                case .loaded(let content):
                    // Moods and genres live on Search, as tiles; Home leads with what is yours.
                    LazyVStack(alignment: .leading, spacing: 30) {
                        sections(content)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                }
            }
            .animation(.smooth, value: model.state.value == nil)
        }
        .navigationTitle(greeting)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsProfile = true } label: { AvatarView(size: 32) }
                    .accessibilityLabel("Profile and Settings")
            }
        }
        .sheet(isPresented: $showsProfile) { ProfileView() }
        .refreshable { await load() }
        .task { if model.state.value == nil { await load() } }
    }

    @ViewBuilder
    private func sections(_ content: HomeModel.Content) -> some View {
        if let mix = model.mix {
            MixHero(mix: mix)
                .padding(.horizontal, 20)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if model.isMixing {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.quaternary)
                .frame(height: 340)
                .placeholderPulse()
                .padding(.horizontal, 20)
        }

        JumpBackIn()

        if !content.quickPicks.isEmpty {
            SongColumnsShelf(title: content.quickPicksTitle, strapline: library.recent.isEmpty ? "Trending now" : "Start with these", songs: content.quickPicks) { index in
                player.play(content.quickPicks, startAt: index)
            }
        }
        if !library.recent.isEmpty {
            ShelfView(title: "Recently played", seeAll: .songs(title: "Recently Played", source: .recent)) {
                ForEach(Array(library.recent.prefix(12).enumerated()), id: \.element.id) { index, song in
                    Button { player.play(Array(library.recent.prefix(50)), startAt: index) } label: {
                        CoverCard(artwork: song.artwork, title: song.title, subtitle: song.artistLine, width: 140)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { SongMenuItems(song: song) } preview: { SongPreview(song: song) }
                }
            }
        }
        if let first = content.shelves.first {
            ItemShelf(shelf: first, onPlay: play)
        }
        let yours = model.topArtists(library)
        if yours.count >= 3 {
            ShelfView(title: "Your top artists", strapline: "Based on your listening") {
                ForEach(yours, id: \.name) { ref in
                    if let id = ref.id {
                        let artist = ArtistSummary(id: id, name: ref.name, artwork: model.artistPhotos[id])
                        NavigationLink(value: Route.artist(artist)) { ArtistCard(artist: artist, width: 112) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        if let releases = content.newReleases {
            ItemShelf(shelf: releases, onPlay: play)
        }
        ForEach(content.shelves.dropFirst()) { shelf in
            ItemShelf(shelf: shelf, onPlay: play)
        }
        if !content.chartArtists.isEmpty {
            ShelfView(title: "Top artists", strapline: "Charts") {
                ForEach(content.chartArtists) { artist in
                    NavigationLink(value: Route.artist(artist)) { ArtistCard(artist: artist) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func play(_ song: Song) {
        player.startRadio(from: song)
    }

    private func load() async {
        await model.load(music: app.music, library: library)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Up late"
        }
    }
}

// MARK: - Your Mix

/// The first thing on Home: the listener's mix as a large card in its covers' colours,
/// with the covers fanned out and a play button that starts it.
private struct MixHero: View {
    let mix: HomeModel.Mix
    @Environment(Player.self) private var player
    /// One palette per fanned-out cover; the background weaves all three together.
    @State private var palettes = [PaletteModel(), PaletteModel(), PaletteModel()]
    @State private var appeared = false
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var covers: [Artwork] {
        var seen = Set<URL>()
        return mix.songs.compactMap(\.artwork).filter { seen.insert($0.url(pixels: 120)).inserted }.prefix(3).map { $0 }
    }

    private var title: String { mix.isPersonal ? "Your Mix" : "Start Here" }

    /// A 3×3 mesh from the three covers: the first cover's colours to the top left, the
    /// second's along the top right and right edge, the third's along the bottom and in
    /// the middle, so the card reads as all of them rather than one. Fewer covers repeat.
    private var meshColors: [Color] {
        let count = max(min(covers.count, 3), 1)
        let a = palettes[0].palette.mesh, b = palettes[1 % count].palette.mesh, c = palettes[2 % count].palette.mesh
        return [
            a[0], a[1], b[2],
            a[3], c[4], b[5],
            c[6], c[7], b[8],
        ]
    }
    private var caption: String {
        guard mix.isPersonal else { return "Trending songs to get Koda to know you" }
        switch mix.artists.count {
        case 0: return "Made from what you play"
        case 1: return "\(mix.artists[0]) and more"
        default: return "\(mix.artists.prefix(2).joined(separator: ", ")) and more"
        }
    }

    var body: some View {
        NavigationLink(value: Route.songList(title: title, subtitle: caption, songs: mix.songs)) {
            ZStack(alignment: .bottomLeading) {
                MixBackground(colors: meshColors, isAnimating: !reduceMotion)
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)

                collage
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 22)
                    .padding(.trailing, 18)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mix.isPersonal ? "MADE FOR YOU" : "NEW HERE")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(title)
                            .font(.system(size: 42, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(caption)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the play button, which sits over the card rather than inside the link.
                    Color.clear.frame(width: 64, height: 64)
                }
                .padding(22)
            }
            .frame(height: 340)
            .clipShape(.rect(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: meshColors[4].opacity(0.35), radius: 24, y: 12)
            .contentShape(.rect(cornerRadius: 32, style: .continuous))
        }
        .buttonStyle(HeroButtonStyle())
        .overlay(alignment: .bottomTrailing) {
            Button {
                taps += 1
                player.play(mix.songs)
            } label: {
                Image(systemName: "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(HeroButtonStyle())
            .padding(22)
            .accessibilityLabel("Play \(title)")
            .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        }
        .task(id: covers) {
            // The covers are already loaded for the collage, so these come from the cache.
            for (index, cover) in covers.enumerated() where index < palettes.count {
                await palettes[index].load(cover)
            }
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.72).delay(0.1)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
    }

    /// Three covers fanned out: one large and tilted, two small circles tucked against it.
    private var collage: some View {
        let covers = covers
        return ZStack(alignment: .topTrailing) {
            if covers.count > 0 {
                ArtworkView(artwork: covers[0], size: 150, cornerRadius: 22)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    .rotationEffect(.degrees(appeared ? 7 : 0))
                    .offset(x: appeared ? -6 : 0, y: appeared ? 4 : 10)
            }
            if covers.count > 1 {
                ArtworkView(artwork: covers[1], size: 78, circle: true)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    .offset(x: appeared ? -132 : -90, y: appeared ? 92 : 70)
            }
            if covers.count > 2 {
                ArtworkView(artwork: covers[2], size: 58, circle: true)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .offset(x: appeared ? -8 : -30, y: appeared ? 150 : 120)
            }
        }
        .opacity(appeared ? 1 : 0)
        .accessibilityHidden(true)
    }
}

/// The mix card's colours, their inner points drifting slowly so the colours move.
private struct MixBackground: View {
    let colors: [Color]
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let a = Float(sin(t * 0.3)) * 0.1, b = Float(cos(t * 0.23)) * 0.1
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + a * 0.6, 0], [1, 0],
                [0, 0.5 + b * 0.6], [0.55 + a, 0.45 + b], [1, 0.5 - a * 0.6],
                [0, 1], [0.5 - b * 0.6, 1], [1, 1],
            ], colors: colors)
        }
        .animation(.easeInOut(duration: 0.8), value: colors)
    }
}

/// Presses down slightly, like a card being pushed.
private struct HeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Jump back in

/// Up to six things the listener keeps going back to, as compact tiles in two columns.
private struct JumpBackIn: View {
    @Environment(Library.self) private var library

    enum Item: Identifiable {
        case liked(count: Int, songs: [Song])
        case userPlaylist(UserPlaylist)
        case album(AlbumSummary)
        case playlist(PlaylistSummary)

        var id: String {
            switch self {
            case .liked: "liked"
            case .userPlaylist(let p): "user-\(p.id)"
            case .album(let a): "album-\(a.id)"
            case .playlist(let p): "playlist-\(p.id)"
            }
        }
    }

    private var items: [Item] {
        var items: [Item] = []
        if !library.liked.isEmpty { items.append(.liked(count: library.liked.count, songs: library.liked)) }
        let playlists = library.userPlaylists.filter { !$0.songs.isEmpty }.sorted { $0.modified > $1.modified }
        items += playlists.prefix(2).map(Item.userPlaylist)
        // Albums of songs played lately, newest first, one each.
        var seenAlbums = Set<String>()
        for song in library.recent {
            guard let album = song.album, seenAlbums.insert(album.id).inserted else { continue }
            items.append(.album(AlbumSummary(id: album.id, title: album.title, artistLine: song.artistLine, artists: song.artists, artwork: song.artwork)))
            if items.count >= 6 { break }
        }
        for album in library.albums where items.count < 6 && seenAlbums.insert(album.id).inserted {
            items.append(.album(album))
        }
        items += library.playlists.prefix(max(0, 6 - items.count)).map(Item.playlist)
        return Array(items.prefix(6))
    }

    var body: some View {
        let items = items
        if items.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Jump back in")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        NavigationLink(value: route(item)) { tile(item) }
                            .buttonStyle(HeroButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func route(_ item: Item) -> Route {
        switch item {
        case .liked: .songs(title: "Liked Songs", source: .liked)
        case .userPlaylist(let p): .userPlaylist(p.id)
        case .album(let a): .album(a)
        case .playlist(let p): .playlist(p)
        }
    }

    private func tile(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Group {
                switch item {
                case .liked(_, let songs):
                    // The listener's own liked covers, marked with a heart, rather than a stock colour.
                    PlaylistMosaic(songs: songs, size: 56, cornerRadius: 0)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(.black.opacity(0.45), in: .circle)
                                .padding(3)
                        }
                case .userPlaylist(let p):
                    PlaylistMosaic(songs: p.songs, size: 56, cornerRadius: 0)
                case .album(let a):
                    ArtworkView(artwork: a.artwork, size: 56, cornerRadius: 0)
                case .playlist(let p):
                    ArtworkView(artwork: p.artwork, size: 56, cornerRadius: 0)
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            VStack(alignment: .leading, spacing: 1) {
                Text(title(item))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = subtitle(item) {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
        .frame(height: 56)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10, style: .continuous))
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .foregroundStyle(.primary)
    }

    private func title(_ item: Item) -> String {
        switch item {
        case .liked: "Liked Songs"
        case .userPlaylist(let p): p.name
        case .album(let a): a.title
        case .playlist(let p): p.title
        }
    }

    private func subtitle(_ item: Item) -> String? {
        switch item {
        case .liked(let count, _): count == 1 ? "1 song" : "\(count) songs"
        case .userPlaylist(let p): p.songs.count == 1 ? "1 song" : "\(p.songs.count) songs"
        case .album(let a): a.artistLine.isEmpty ? nil : a.artistLine
        case .playlist(let p): p.subtitle
        }
    }
}

// MARK: - Loading

/// The shape of Home in shimmering placeholders while it loads.
private struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.quaternary)
                .frame(height: 340)
                .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary).frame(height: 56)
                }
            }
            .padding(.horizontal, 20)
            HStack(spacing: 14) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary).frame(width: 140, height: 140)
                }
            }
            .padding(.horizontal, 20)
        }
        .placeholderPulse()
        .padding(.top, 8)
        .accessibilityLabel("Loading")
    }
}
