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
        var topArtists: [ArtistSummary] = []
        var moods: [Mood] = []
    }

    private(set) var state: LoadState<Content> = .loading
    private(set) var moodState: LoadState<[Shelf]>?
    private(set) var selectedMood: Mood?

    func load(music: YouTubeMusic, recent: [Song]) async {
        if state.value == nil { state = .loading }
        async let home = music.home()
        async let explore = try? music.explore()
        async let charts = try? music.charts()
        async let picks = quickPicks(music: music, recent: recent)
        do {
            let homePage = try await home
            var content = Content()
            content.shelves = homePage.shelves
            content.moods = homePage.moods
            let explorePage = await explore
            content.newReleases = explorePage?.shelves.first { $0.title == "New albums & singles" }
            content.topArtists = (await charts)?.shelves.first { $0.title == "Top artists" }?.items.compactMap {
                if case .artist(let a) = $0 { return a }
                return nil
            } ?? []
            let (title, songs) = await picks
            content.quickPicksTitle = title
            content.quickPicks = songs.isEmpty ? trending(explorePage) : songs
            state = .loaded(content)
        } catch {
            if state.value == nil { state = .failed(error.friendlyMessage) }
        }
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

    func select(_ mood: Mood?, music: YouTubeMusic) async {
        selectedMood = mood
        guard let mood else {
            moodState = nil
            return
        }
        moodState = .loading
        do {
            let page = try await music.home(params: mood.params)
            guard selectedMood == mood else { return }
            moodState = .loaded(page.shelves)
        } catch {
            guard selectedMood == mood else { return }
            moodState = .failed(error.friendlyMessage)
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var model = HomeModel()
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            AsyncContent(state: model.state, retry: load) { content in
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !content.moods.isEmpty {
                        MoodChips(moods: content.moods, selected: model.selectedMood) { mood in
                            Task { await model.select(mood, music: app.music) }
                        }
                    }
                    if let moodState = model.moodState {
                        AsyncContent(state: moodState, retry: { await model.select(model.selectedMood, music: app.music) }) { shelves in
                            ForEach(shelves) { shelf in ItemShelf(shelf: shelf, onPlay: play) }
                        }
                    } else {
                        sections(content)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(greeting)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .refreshable { await load() }
        .task { if model.state.value == nil { await load() } }
    }

    @ViewBuilder
    private func sections(_ content: HomeModel.Content) -> some View {
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
        if !content.quickPicks.isEmpty {
            SongColumnsShelf(title: content.quickPicksTitle, strapline: library.recent.isEmpty ? "Trending now" : "Start with these", songs: content.quickPicks) { index in
                player.play(content.quickPicks, startAt: index)
            }
        }
        if let first = content.shelves.first {
            ItemShelf(shelf: first, onPlay: play)
        }
        if let releases = content.newReleases {
            ItemShelf(shelf: releases, onPlay: play)
        }
        ForEach(content.shelves.dropFirst()) { shelf in
            ItemShelf(shelf: shelf, onPlay: play)
        }
        if !content.topArtists.isEmpty {
            ShelfView(title: "Top artists") {
                ForEach(content.topArtists) { artist in
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
        await model.load(music: app.music, recent: library.recent)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }
}

/// Mood and genre filters across the top of Home; tapping the selected one clears it.
struct MoodChips: View {
    let moods: [Mood]
    let selected: Mood?
    let onSelect: (Mood?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(moods) { mood in
                    let isSelected = mood == selected
                    Button(mood.title) { onSelect(isSelected ? nil : mood) }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(isSelected ? .accentColor : .secondary)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .sensoryFeedback(.selection, trigger: isSelected)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }
}
