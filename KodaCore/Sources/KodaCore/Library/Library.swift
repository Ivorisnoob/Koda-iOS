import Foundation
import Observation

/// What the listener keeps on this phone: songs they liked, albums, playlists
/// and artists they saved, what they played and searched. One JSON file,
/// written after each change.
@MainActor
@Observable
public final class Library {
    public private(set) var liked: [Song] = []
    public private(set) var albums: [AlbumSummary] = []
    public private(set) var playlists: [PlaylistSummary] = []
    public private(set) var artists: [ArtistSummary] = []
    /// Most recent first, one entry per song.
    public private(set) var recent: [Song] = []
    public private(set) var searches: [String] = []

    private let file: URL?
    private static let recentLimit = 200
    private static let searchLimit = 20

    public init(directory: URL?) {
        file = directory?.appending(path: "library.json")
        load()
    }

    // MARK: Songs

    public func isLiked(_ song: Song) -> Bool { liked.contains { $0.id == song.id } }

    public func toggleLike(_ song: Song) {
        if let index = liked.firstIndex(where: { $0.id == song.id }) {
            liked.remove(at: index)
        } else {
            liked.insert(song, at: 0)
        }
        save()
    }

    public func recordPlay(_ song: Song) {
        recent.removeAll { $0.id == song.id }
        recent.insert(song, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        save()
    }

    public func clearHistory() {
        recent = []
        save()
    }

    // MARK: Collections

    public func isSaved(album id: String) -> Bool { albums.contains { $0.id == id } }
    public func isSaved(playlist id: String) -> Bool { playlists.contains { $0.id == id } }
    public func isSaved(artist id: String) -> Bool { artists.contains { $0.id == id } }

    public func toggleSave(_ album: AlbumSummary) {
        toggle(album, in: &albums)
        save()
    }

    public func toggleSave(_ playlist: PlaylistSummary) {
        toggle(playlist, in: &playlists)
        save()
    }

    public func toggleSave(_ artist: ArtistSummary) {
        toggle(artist, in: &artists)
        save()
    }

    private func toggle<T: Identifiable>(_ item: T, in list: inout [T]) {
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list.remove(at: index)
        } else {
            list.insert(item, at: 0)
        }
    }

    // MARK: Search history

    public func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searches.insert(trimmed, at: 0)
        if searches.count > Self.searchLimit { searches.removeLast(searches.count - Self.searchLimit) }
        save()
    }

    public func removeSearch(_ query: String) {
        searches.removeAll { $0 == query }
        save()
    }

    public func clearSearches() {
        searches = []
        save()
    }

    // MARK: Storage

    private struct Snapshot: Codable {
        var liked: [Song] = []
        var albums: [AlbumSummary] = []
        var playlists: [PlaylistSummary] = []
        var artists: [ArtistSummary] = []
        var recent: [Song] = []
        var searches: [String] = []
    }

    private func load() {
        guard let file, let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        liked = snapshot.liked
        albums = snapshot.albums
        playlists = snapshot.playlists
        artists = snapshot.artists
        recent = snapshot.recent
        searches = snapshot.searches
    }

    private func save() {
        guard let file else { return }
        let snapshot = Snapshot(liked: liked, albums: albums, playlists: playlists, artists: artists, recent: recent, searches: searches)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
