import Foundation
import Observation

/// What the listener keeps on this phone: songs they liked, albums, playlists
/// and artists they saved, playlists they made, what they played and searched,
/// and how long they listened. One JSON file, written after each change.
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
    /// Playlists made on this phone, newest first.
    public private(set) var userPlaylists: [UserPlaylist] = []
    /// Play counts and listening time per song, by video id.
    public private(set) var songStats: [String: SongStats] = [:]
    /// Seconds listened per day, keyed `yyyy-MM-dd` in the phone's time zone.
    public private(set) var dailyListening: [String: TimeInterval] = [:]
    /// Seconds to shift synced lyrics by, per video id; positive shows lines later.
    public private(set) var lyricsOffsets: [String: TimeInterval] = [:]

    private let file: URL?
    private static let recentLimit = 200
    private static let searchLimit = 20
    /// Listening time arrives every few seconds; it is written with the next change or `flush()`.
    private var hasUnsavedListening = false

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

    public func recordPlay(_ song: Song, at date: Date = Date()) {
        recent.removeAll { $0.id == song.id }
        recent.insert(song, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        var stats = songStats[song.id] ?? SongStats(song: song, firstPlayed: date)
        stats.song = song
        stats.plays += 1
        stats.lastPlayed = date
        songStats[song.id] = stats
        save()
    }

    /// Credit `seconds` of listening to `song` on the day of `date`.
    public func addListening(_ seconds: TimeInterval, to song: Song, at date: Date = Date()) {
        guard seconds > 0 else { return }
        var stats = songStats[song.id] ?? SongStats(song: song, firstPlayed: date)
        stats.seconds += seconds
        songStats[song.id] = stats
        dailyListening[Self.dayKey(date), default: 0] += seconds
        hasUnsavedListening = true
    }

    /// Write listening time gathered since the last save.
    public func flush() {
        if hasUnsavedListening { save() }
    }

    public func clearHistory() {
        recent = []
        save()
    }

    /// Forget play counts and listening time; history and likes stay.
    public func clearStats() {
        songStats = [:]
        dailyListening = [:]
        save()
    }

    public func plays(of song: Song) -> Int { songStats[song.id]?.plays ?? 0 }

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

    // MARK: Playlists made here

    public func userPlaylist(_ id: UUID) -> UserPlaylist? { userPlaylists.first { $0.id == id } }

    @discardableResult
    public func createPlaylist(named name: String, songs: [Song] = [], at date: Date = Date()) -> UserPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = UserPlaylist(name: trimmed.isEmpty ? "New Playlist" : trimmed, songs: Self.unique(songs), created: date)
        userPlaylists.insert(playlist, at: 0)
        save()
        return playlist
    }

    public func renamePlaylist(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editPlaylist(id) { $0.name = trimmed }
    }

    public func deletePlaylist(_ id: UUID) {
        userPlaylists.removeAll { $0.id == id }
        save()
    }

    /// Append the songs the playlist does not already hold; returns how many were added.
    @discardableResult
    public func add(_ songs: [Song], toPlaylist id: UUID) -> Int {
        var added = 0
        editPlaylist(id) { playlist in
            let known = Set(playlist.songs.map(\.id))
            let fresh = Self.unique(songs).filter { !known.contains($0.id) }
            playlist.songs += fresh
            added = fresh.count
        }
        return added
    }

    public func removeSongs(atOffsets offsets: IndexSet, fromPlaylist id: UUID) {
        editPlaylist(id) { playlist in
            for index in offsets.sorted(by: >) where playlist.songs.indices.contains(index) {
                playlist.songs.remove(at: index)
            }
        }
    }

    public func moveSongs(fromOffsets source: IndexSet, toOffset destination: Int, inPlaylist id: UUID) {
        editPlaylist(id) { playlist in
            let valid = source.filter { playlist.songs.indices.contains($0) }
            guard !valid.isEmpty else { return }
            let moving = valid.map { playlist.songs[$0] }
            let insertAt = min(max(destination, 0), playlist.songs.count) - valid.filter { $0 < destination }.count
            for index in valid.reversed() { playlist.songs.remove(at: index) }
            playlist.songs.insert(contentsOf: moving, at: insertAt)
        }
    }

    private func editPlaylist(_ id: UUID, _ change: (inout UserPlaylist) -> Void) {
        guard let index = userPlaylists.firstIndex(where: { $0.id == id }) else { return }
        change(&userPlaylists[index])
        userPlaylists[index].modified = Date()
        save()
    }

    private static func unique(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.id).inserted }
    }

    // MARK: Lyrics timing

    public func lyricsOffset(for songId: String) -> TimeInterval { lyricsOffsets[songId] ?? 0 }

    /// Rounded to a tenth of a second; zero removes the entry.
    public func setLyricsOffset(_ offset: TimeInterval, for songId: String) {
        let rounded = (offset * 10).rounded() / 10
        lyricsOffsets[songId] = rounded == 0 ? nil : rounded
        save()
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

    // MARK: Days

    nonisolated static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Seconds listened on the day of `date`.
    public func listening(on date: Date, calendar: Calendar = .current) -> TimeInterval {
        dailyListening[Self.dayKey(date, calendar: calendar)] ?? 0
    }

    /// Days in a row with any listening, ending today, or yesterday while today has none yet.
    public func streak(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if listening(on: day, calendar: calendar) == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var count = 0
        while listening(on: day, calendar: calendar) > 0 {
            count += 1
            guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = before
        }
        return count
    }

    // MARK: Storage

    private struct Snapshot: Codable {
        var liked: [Song] = []
        var albums: [AlbumSummary] = []
        var playlists: [PlaylistSummary] = []
        var artists: [ArtistSummary] = []
        var recent: [Song] = []
        var searches: [String] = []
        var userPlaylists: [UserPlaylist] = []
        var songStats: [String: SongStats] = [:]
        var dailyListening: [String: TimeInterval] = [:]
        var lyricsOffsets: [String: TimeInterval] = [:]

        init() {}

        // A file from an older version lacks the newer keys; each missing one starts empty rather than failing the whole file.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            liked = try c.decodeIfPresent([Song].self, forKey: .liked) ?? []
            albums = try c.decodeIfPresent([AlbumSummary].self, forKey: .albums) ?? []
            playlists = try c.decodeIfPresent([PlaylistSummary].self, forKey: .playlists) ?? []
            artists = try c.decodeIfPresent([ArtistSummary].self, forKey: .artists) ?? []
            recent = try c.decodeIfPresent([Song].self, forKey: .recent) ?? []
            searches = try c.decodeIfPresent([String].self, forKey: .searches) ?? []
            userPlaylists = try c.decodeIfPresent([UserPlaylist].self, forKey: .userPlaylists) ?? []
            songStats = try c.decodeIfPresent([String: SongStats].self, forKey: .songStats) ?? [:]
            dailyListening = try c.decodeIfPresent([String: TimeInterval].self, forKey: .dailyListening) ?? [:]
            lyricsOffsets = try c.decodeIfPresent([String: TimeInterval].self, forKey: .lyricsOffsets) ?? [:]
        }
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
        userPlaylists = snapshot.userPlaylists
        songStats = snapshot.songStats
        dailyListening = snapshot.dailyListening
        lyricsOffsets = snapshot.lyricsOffsets
    }

    private func save() {
        hasUnsavedListening = false
        guard let file else { return }
        var snapshot = Snapshot()
        snapshot.liked = liked
        snapshot.albums = albums
        snapshot.playlists = playlists
        snapshot.artists = artists
        snapshot.recent = recent
        snapshot.searches = searches
        snapshot.userPlaylists = userPlaylists
        snapshot.songStats = songStats
        snapshot.dailyListening = dailyListening
        snapshot.lyricsOffsets = lyricsOffsets
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// A playlist made on this phone.
public struct UserPlaylist: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var songs: [Song]
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), name: String, songs: [Song] = [], created: Date = Date()) {
        self.id = id
        self.name = name
        self.songs = songs
        self.created = created
        modified = created
    }

    public var duration: TimeInterval { songs.compactMap(\.duration).reduce(0, +) }
}

/// How much one song has been played.
public struct SongStats: Hashable, Codable, Sendable {
    public var song: Song
    public var plays = 0
    public var seconds: TimeInterval = 0
    public var firstPlayed: Date
    public var lastPlayed: Date

    public init(song: Song, firstPlayed: Date) {
        self.song = song
        self.firstPlayed = firstPlayed
        lastPlayed = firstPlayed
    }
}
