import Foundation

/// What the listener plays most lately, from the library's counts: the seeds for Your Mix.
///
/// Each song scores its plays and listening time, weighed by how recently it was
/// last played: a song last played two weeks ago counts half as much as one from
/// today. Liked songs get a bonus. Artists score the sum of their songs.
public struct Taste: Sendable, Equatable {
    /// Lead artists, strongest first.
    public var artists: [String]
    /// One favourite song per top artist, strongest first, to start radios from.
    public var seeds: [Song]

    public var isEmpty: Bool { seeds.isEmpty }

    static let halfLife: TimeInterval = 14 * 86_400

    public init(artists: [String], seeds: [Song]) {
        self.artists = artists
        self.seeds = seeds
    }

    @MainActor
    public init(library: Library, now: Date = Date(), maxSeeds: Int = 4) {
        let liked = Set(library.liked.map(\.id))
        let scored = library.songStats.values.map { stats -> (SongStats, Double) in
            let age = max(0, now.timeIntervalSince(stats.lastPlayed))
            let decay = pow(0.5, age / Self.halfLife)
            let listening = Double(stats.plays) + stats.seconds / 180
            return (stats, (listening + (liked.contains(stats.song.id) ? 2 : 0)) * decay)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.song.id < $1.0.song.id }

        var artistScores: [String: Double] = [:]
        for (stats, score) in scored {
            artistScores[Self.leadArtist(stats.song), default: 0] += score
        }
        let artists = artistScores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key).filter { !$0.isEmpty }

        var seeds: [Song] = []
        for artist in artists where seeds.count < maxSeeds {
            if let best = scored.first(where: { Self.leadArtist($0.0.song) == artist }) { seeds.append(best.0.song) }
        }
        self.artists = artists
        self.seeds = seeds
    }

    static func leadArtist(_ song: Song) -> String {
        song.artists.first?.name ?? song.artistLine
    }

    /// Radios woven together a song at a time, so no one artist's radio takes over;
    /// songs heard in more than one radio, and the seeds themselves, appear once.
    public static func weave(_ radios: [[Song]], excluding: Set<String> = [], limit: Int = 50) -> [Song] {
        var seen = excluding
        var out: [Song] = []
        let longest = radios.map(\.count).max() ?? 0
        for index in 0..<longest {
            for radio in radios where index < radio.count {
                let song = radio[index]
                if seen.insert(song.id).inserted { out.append(song) }
                if out.count == limit { return out }
            }
        }
        return out
    }
}
