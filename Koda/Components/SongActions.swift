import KodaCore
import SwiftUI

/// What can be done with a song, shared by its long-press menu and its ellipsis button.
struct SongMenuItems: View {
    let song: Song
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library

    var body: some View {
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext([song]) }
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue([song]) }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") { player.startRadio(from: song) }
        }
        Section {
            let liked = library.isLiked(song)
            Button(liked ? "Remove from Liked" : "Like", systemImage: liked ? "heart.slash" : "heart") { library.toggleLike(song) }
            if let album = song.album {
                Button("Go to Album", systemImage: "square.stack") {
                    model.open(.album(AlbumSummary(id: album.id, title: album.title, artistLine: song.artistLine, artists: song.artists, artwork: song.artwork)))
                }
            }
            if let artist = song.artists.first(where: { $0.id != nil }), let id = artist.id {
                Button("Go to Artist", systemImage: "music.mic") { model.open(.artist(ArtistSummary(id: id, name: artist.name))) }
            }
            ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(song.id)")!) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// The ellipsis button at the end of a song row.
struct SongMenuButton: View {
    let song: Song

    var body: some View {
        Menu {
            SongMenuItems(song: song)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
    }
}
