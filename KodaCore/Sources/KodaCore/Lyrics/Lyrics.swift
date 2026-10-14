import Foundation

public struct LyricLine: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Seconds from the start of the song.
    public var time: TimeInterval
    public var text: String
}

public enum Lyrics: Sendable, Equatable {
    case synced([LyricLine])
    case plain(String)

    /// The line playing at `time`: the last one that has started.
    public static func index(of time: TimeInterval, in lines: [LyricLine]) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// `[mm:ss.xx] text` lines. Several stamps on one line repeat it; lines without one are dropped.
    public static func parseLRC(_ text: String) -> [LyricLine] {
        var lines: [(TimeInterval, String)] = []
        let stamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/
        for raw in text.split(whereSeparator: \.isNewline) {
            let matches = raw.matches(of: stamp)
            guard let last = matches.last else { continue }
            let words = raw[last.range.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(match.output.1) ?? 0
                let seconds = Double(match.output.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                lines.append((minutes * 60 + seconds, words))
            }
        }
        return lines.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

/// Lyrics from LRCLIB, matched by artist, title and length.
public struct LyricsClient: Sendable {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lyrics(for song: Song) async -> Lyrics? {
        let artist = song.artists.first?.name ?? song.artistLine
        if let exact = await get(artist: artist, title: song.title, album: song.album?.title, duration: song.duration) {
            return exact
        }
        return await search(artist: artist, title: song.title, duration: song.duration)
    }

    private func get(artist: String, title: String, album: String?, duration: TimeInterval?) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "track_name", value: title)]
        if let album { components.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration { components.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        guard let json = await fetch(components.url!), json.isObject else { return nil }
        return Self.lyrics(from: json)
    }

    private func search(artist: String, title: String, duration: TimeInterval?) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "track_name", value: title)]
        guard let json = await fetch(components.url!) else { return nil }
        // A different cut of the song (live, extended) is timed for a different recording.
        let candidates = json.array.filter { item in
            guard let duration, let other = item["duration"].double else { return true }
            return abs(other - duration) <= 10
        }
        let best = candidates.first { $0["syncedLyrics"].nonEmpty != nil } ?? candidates.first
        return best.flatMap(Self.lyrics(from:))
    }

    private func fetch(_ url: URL) async -> JSON? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Koda iOS (https://github.com/Ivorisnoob/Koda-iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSON(data: data)
    }

    static func lyrics(from item: JSON) -> Lyrics? {
        if let synced = item["syncedLyrics"].nonEmpty {
            let lines = Lyrics.parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = item["plainLyrics"].nonEmpty { return .plain(plain) }
        return nil
    }
}
