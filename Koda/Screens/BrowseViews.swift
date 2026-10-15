import KodaCore
import SwiftUI

/// A mood or genre's page of shelves.
struct MoodView: View {
    let mood: Mood
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @State private var state: LoadState<[Shelf]> = .loading

    var body: some View {
        ScrollView {
            AsyncContent(state: state, retry: load) { shelves in
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(shelves) { shelf in
                        ItemShelf(shelf: shelf) { player.startRadio(from: $0) }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(mood.title)
        .task { if state.value == nil { await load() } }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await app.music.mood(mood).shelves)
        } catch {
            state = .failed(error.friendlyMessage)
        }
    }
}

/// Every item of a shelf, in a grid.
struct ShelfGridView: View {
    let shelf: Shelf
    @Environment(Player.self) private var player

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16, alignment: .top)], spacing: 20) {
                ForEach(shelf.items) { item in
                    ItemCard(item: item, width: 160) { player.startRadio(from: $0) }
                }
            }
            .padding(20)
        }
        .navigationTitle(shelf.title)
    }
}

/// Liked songs or recently played, from the library on this phone.
struct SavedSongsView: View {
    let title: String
    let source: Route.SongSource
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(Downloads.self) private var downloads
    @AppStorage("koda.likedSort") private var sort: SongSort = .recent

    private var songs: [Song] {
        switch source {
        case .recent: return library.recent
        case .downloaded: return downloads.songs
        case .liked: break
        }
        let liked = library.liked
        switch sort {
        case .recent: return liked
        case .title: return liked.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return liked.sorted { $0.artistLine.localizedStandardCompare($1.artistLine) == .orderedAscending }
        case .mostPlayed:
            // Stable for ties: songs played as often keep the order they were liked in.
            return liked.enumerated().sorted { a, b in
                let pa = library.plays(of: a.element), pb = library.plays(of: b.element)
                return pa != pb ? pa > pb : a.offset < b.offset
            }.map(\.element)
        }
    }

    var body: some View {
        List {
            if !songs.isEmpty {
                PlayShuffleButtons(play: { player.play(songs) }, shuffle: {
                    player.play(songs, startAt: Int.random(in: 0..<songs.count), shuffled: true)
                })
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song) { player.play(songs, startAt: index) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
                    .swipeActions(edge: .leading) {
                        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext([song]) }
                            .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing) {
                        switch source {
                        case .liked:
                            Button("Unlike", systemImage: "heart.slash", role: .destructive) { library.toggleLike(song) }
                        case .downloaded:
                            Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove([song]) }
                        case .recent:
                            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue([song]) }
                                .tint(.orange)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty {
                switch source {
                case .liked:
                    ContentUnavailableView("No Liked Songs", systemImage: "heart", description: Text("Songs you like appear here."))
                case .recent:
                    ContentUnavailableView("Nothing Played Yet", systemImage: "clock", description: Text("Songs you play appear here."))
                case .downloaded:
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                           description: Text("Download songs, albums and playlists to play them without a connection."))
                }
            }
        }
        .toolbar {
            if source == .recent, !songs.isEmpty {
                Button("Clear", role: .destructive) { library.clearHistory() }
            }
            if source == .liked, !songs.isEmpty {
                DownloadButton(songs: songs)
            }
            if source == .liked, songs.count > 1 {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort By", selection: $sort) {
                        ForEach(SongSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

/// How liked songs are ordered.
enum SongSort: String, CaseIterable, Identifiable {
    case recent, title, artist, mostPlayed

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recently Liked"
        case .title: "Title"
        case .artist: "Artist"
        case .mostPlayed: "Most Played"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .title: "textformat"
        case .artist: "music.mic"
        case .mostPlayed: "flame"
        }
    }
}

/// A list of songs the app put together, with play and shuffle.
struct SongListView: View {
    let title: String
    let subtitle: String?
    let songs: [Song]
    @Environment(Player.self) private var player
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 14) {
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                PlayShuffleButtons(play: { player.play(songs) }, shuffle: {
                    player.play(songs, startAt: Int.random(in: 0..<max(songs.count, 1)), shuffled: true)
                })
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song) { player.play(songs, startAt: index) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
                    .swipeActions(edge: .leading) {
                        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext([song]) }
                            .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue([song]) }
                            .tint(.orange)
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .toolbar {
            Menu("More", systemImage: "ellipsis") {
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue(songs) }
                Button("Add to Playlist…", systemImage: "text.badge.plus") { app.addToPlaylist(songs) }
            }
        }
    }
}
