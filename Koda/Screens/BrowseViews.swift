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

    private var songs: [Song] { source == .liked ? library.liked : library.recent }

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
                        if source == .liked {
                            Button("Unlike", systemImage: "heart.slash", role: .destructive) { library.toggleLike(song) }
                        } else {
                            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue([song]) }
                                .tint(.orange)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView(source == .liked ? "No Liked Songs" : "Nothing Played Yet",
                                       systemImage: source == .liked ? "heart" : "clock",
                                       description: Text(source == .liked ? "Songs you like appear here." : "Songs you play appear here."))
            }
        }
        .toolbar {
            if source == .recent, !songs.isEmpty {
                Button("Clear", role: .destructive) { library.clearHistory() }
            }
        }
        .navigationTitle(title)
    }
}
