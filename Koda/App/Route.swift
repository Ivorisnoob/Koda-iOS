import KodaCore
import SwiftUI

/// Every page a navigation stack can push.
enum Route: Hashable {
    case album(AlbumSummary)
    case artist(ArtistSummary)
    case playlist(PlaylistSummary)
    case mood(Mood)
    /// A plain list of songs the app already holds: liked, recently played.
    case songs(title: String, source: SongSource)
    case shelf(Shelf)
    /// A playlist made on this phone.
    case userPlaylist(UUID)
    /// Listening statistics in full.
    case stats

    enum SongSource: Hashable {
        case liked, recent
    }

    init?(_ item: MusicItem) {
        switch item {
        case .album(let a): self = .album(a)
        case .artist(let a): self = .artist(a)
        case .playlist(let p): self = .playlist(p)
        case .song: return nil
        }
    }
}

extension View {
    /// The destinations every tab's stack can reach.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .album(let album): AlbumView(summary: album)
            case .artist(let artist): ArtistView(summary: artist)
            case .playlist(let playlist): PlaylistView(summary: playlist)
            case .mood(let mood): MoodView(mood: mood)
            case .songs(let title, let source): SavedSongsView(title: title, source: source)
            case .shelf(let shelf): ShelfGridView(shelf: shelf)
            case .userPlaylist(let id): UserPlaylistView(id: id)
            case .stats: StatsView()
            }
        }
    }
}
