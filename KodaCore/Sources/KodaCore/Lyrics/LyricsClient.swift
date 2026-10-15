import Foundation

/// Lyrics from several services at once, keeping the best: word-timed from
/// YouLyPlus or BetterLyrics (Apple Music's timings), else line-timed or plain
/// from LRCLIB.
///
/// The services answer at different speeds and come and go. All of them are
/// asked together; a word-timed answer is taken as soon as every service ranked
/// above it has answered, and otherwise the best answer by the deadline.
public struct LyricsClient: Sendable {
    let session: URLSession
    private static let cache = LyricsCache()
    private static let deadline: Duration = .seconds(9)

    private static let youLyPlusMirrors = [
        "https://lyricsplus.binimum.org/",
        "https://lyricsplus.prjktla.my.id/",
        "https://lyricsplus.prjktla.workers.dev/",
        "https://lyricsplus.atomix.one/",
        "https://lyricsplus-seven.vercel.app/",
    ]

    private static let betterLyricsEndpoints = [
        "https://lyrics-api.boidu.dev/getLyrics",
        "https://lyrics-api.boidu.dev/qq/getLyrics",
        "https://lyrics-api.boidu.dev/kugou/getLyrics",
    ]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    struct Query: Sendable {
        var title: String
        var artist: String
        var album: String?
        var duration: TimeInterval?
    }

    public func lyrics(for song: Song) async -> Lyrics? {
        if let cached = await Self.cache[song.id] { return cached }
        let query = Query(title: song.title, artist: song.artists.first?.name ?? song.artistLine,
                          album: song.album?.title, duration: song.duration)
        let found = await best(query)
        if let found { await Self.cache.store(found, for: song.id) }
        return found
    }

    // MARK: Choosing

    private func best(_ query: Query) async -> Lyrics? {
        let providers: [@Sendable () async -> Lyrics?] = [
            { await youLyPlus(query) },
            { await betterLyrics(query) },
            { await lrclib(query) },
        ]
        return await withTaskGroup(of: (Int, Lyrics?)?.self) { group in
            for (rank, provider) in providers.enumerated() {
                group.addTask { (rank, await provider()) }
            }
            group.addTask {
                try? await Task.sleep(for: Self.deadline)
                return nil
            }
            var answers: [Int: Lyrics] = [:]
            var pending = Set(providers.indices)
            while let next = await group.next() {
                // nil is the deadline.
                guard let answer = next else { break }
                let (rank, lyrics) = answer
                pending.remove(rank)
                if let lyrics { answers[rank] = lyrics }
                // Word timing from the best-ranked service still in the running wins outright.
                if let top = answers.filter({ $0.value.quality == 2 }).min(by: { $0.key < $1.key }),
                   !pending.contains(where: { $0 < top.key }) {
                    group.cancelAll()
                    return top.value
                }
                if pending.isEmpty { break }
            }
            group.cancelAll()
            return answers.max { a, b in a.value.quality != b.value.quality ? a.value.quality < b.value.quality : a.key > b.key }?.value
        }
    }

    // MARK: YouLyPlus

    private func youLyPlus(_ query: Query) async -> Lyrics? {
        guard !query.artist.isEmpty else { return nil }
        var parameters = ["title": query.title, "artist": query.artist]
        if let album = query.album, !album.isEmpty { parameters["album"] = album }
        if let duration = query.duration, duration > 0 { parameters["duration"] = String(Int(duration.rounded())) }
        if let found = await race(Self.youLyPlusMirrors.map { $0 + "v2/lyrics/get" }, parameters, decode: { data in
            guard let json = try? JSON(data: data), let lines = Lyrics.parseYouLyPlus(json) else { return nil }
            return .synced(lines)
        }) {
            return found
        }
        return await race(Self.youLyPlusMirrors.map { $0 + "v1/ttml/get" }, parameters, decode: { Self.decodeWrapped($0) })
    }

    /// The first mirror to answer with lyrics; the others are cancelled.
    private func race(_ urls: [String], _ parameters: [String: String], decode: @escaping @Sendable (Data) -> Lyrics?) async -> Lyrics? {
        await withTaskGroup(of: Lyrics?.self) { group in
            for url in urls {
                group.addTask {
                    guard let data = await fetch(url, parameters) else { return nil }
                    return decode(data)
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    // MARK: BetterLyrics

    private func betterLyrics(_ query: Query) async -> Lyrics? {
        guard !query.artist.isEmpty else { return nil }
        var parameters = ["s": query.title, "a": query.artist]
        if let album = query.album, !album.isEmpty { parameters["al"] = album }
        if let duration = query.duration, duration > 0 { parameters["d"] = String(Int(duration.rounded())) }
        for endpoint in Self.betterLyricsEndpoints {
            if Task.isCancelled { return nil }
            if let data = await fetch(endpoint, parameters), let found = Self.decodeWrapped(data) { return found }
        }
        return nil
    }

    /// TTML or LRC as the body, or inside a JSON object under a key such as `ttml` or `lyrics`.
    static func decodeWrapped(_ data: Data) -> Lyrics? {
        guard let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if body.hasPrefix("<") { return Lyrics.parseAny(body) }
        guard let json = try? JSON(data: data) else { return nil }
        for key in ["ttml", "lyrics", "lrc", "content", "text"] {
            if let text = json[key].nonEmpty, let lyrics = Lyrics.parseAny(text) { return lyrics }
        }
        return nil
    }

    // MARK: LRCLIB

    private func lrclib(_ query: Query) async -> Lyrics? {
        var exact = ["artist_name": query.artist, "track_name": query.title]
        if let album = query.album { exact["album_name"] = album }
        if let duration = query.duration { exact["duration"] = String(Int(duration.rounded())) }
        if let data = await fetch("https://lrclib.net/api/get", exact), let json = try? JSON(data: data), json.isObject,
           let found = Self.lrclibLyrics(from: json) {
            return found
        }
        guard let data = await fetch("https://lrclib.net/api/search", ["artist_name": query.artist, "track_name": query.title]),
              let json = try? JSON(data: data) else { return nil }
        // A different cut of the song (live, extended) is timed for a different recording.
        let candidates = json.array.filter { item in
            guard let duration = query.duration, let other = item["duration"].double else { return true }
            return abs(other - duration) <= 10
        }
        let best = candidates.first { $0["syncedLyrics"].nonEmpty != nil } ?? candidates.first
        return best.flatMap(Self.lrclibLyrics(from:))
    }

    static func lrclibLyrics(from item: JSON) -> Lyrics? {
        if let synced = item["syncedLyrics"].nonEmpty {
            let lines = Lyrics.parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = item["plainLyrics"].nonEmpty { return .plain(plain) }
        return nil
    }

    // MARK: Network

    private func fetch(_ url: String, _ parameters: [String: String]) async -> Data? {
        guard var components = URLComponents(string: url) else { return nil }
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Koda iOS (https://github.com/Ivorisnoob/Koda-iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/xml, text/plain, */*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status), !data.isEmpty else { return nil }
        return data
    }
}

/// Lyrics already found this session, so reopening the panel or replaying a song is instant.
private actor LyricsCache {
    private var entries: [String: Lyrics] = [:]
    private var order: [String] = []

    subscript(id: String) -> Lyrics? { entries[id] }

    func store(_ lyrics: Lyrics, for id: String) {
        if entries[id] == nil { order.append(id) }
        entries[id] = lyrics
        if order.count > 60 { entries[order.removeFirst()] = nil }
    }
}
