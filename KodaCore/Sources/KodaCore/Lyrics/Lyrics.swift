import Foundation

/// One sung word, or part of one: providers split long words into syllables.
public struct LyricWord: Hashable, Sendable {
    public var text: String
    /// Seconds from the start of the song.
    public var start: TimeInterval
    public var end: TimeInterval
    /// A space follows before the next word; false between syllables of one word.
    public var spaceAfter: Bool

    public init(text: String, start: TimeInterval, end: TimeInterval, spaceAfter: Bool = true) {
        self.text = text
        self.start = start
        self.end = end
        self.spaceAfter = spaceAfter
    }

    public var duration: TimeInterval { max(end - start, 0.001) }
}

/// Who sings a line, when the lyrics say.
public enum LyricVoice: Hashable, Sendable {
    /// The main singer, or the only one.
    case lead
    /// The second singer of a duet.
    case duet
    /// Several singers at once.
    case together
}

public struct LyricLine: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Seconds from the start of the song.
    public var time: TimeInterval
    public var text: String
    /// Word timings, when the provider has them; empty for line-timed lyrics.
    public var words: [LyricWord]
    /// Backing vocals sung over the line, timed the same way.
    public var background: [LyricWord]
    /// When the line is done; nil when only its start is known.
    public var end: TimeInterval?
    public var voice: LyricVoice

    public init(id: Int, time: TimeInterval, text: String, words: [LyricWord] = [], background: [LyricWord] = [],
                end: TimeInterval? = nil, voice: LyricVoice = .lead) {
        self.id = id
        self.time = time
        self.text = text
        self.words = words
        self.background = background
        self.end = end
        self.voice = voice
    }

    public var isWordTimed: Bool { !words.isEmpty }
}

public enum Lyrics: Sendable, Equatable {
    case synced([LyricLine])
    case plain(String)

    /// Word timing beats line timing beats none.
    var quality: Int {
        switch self {
        case .plain: 0
        case .synced(let lines): lines.contains(where: \.isWordTimed) ? 2 : 1
        }
    }

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

    /// `[mm:ss.xx] text` lines, with `<mm:ss.xx>` word stamps when the file has them
    /// (enhanced LRC). Several line stamps repeat the line; lines without one are dropped.
    public static func parseLRC(_ text: String) -> [LyricLine] {
        struct Raw { var time: TimeInterval; var text: String; var words: [LyricWord] }
        var lines: [Raw] = []
        let stamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/
        let wordStamp = /<(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)>/
        func seconds(_ minutes: Substring, _ rest: Substring) -> TimeInterval {
            (Double(minutes) ?? 0) * 60 + (Double(rest.replacingOccurrences(of: ":", with: ".")) ?? 0)
        }
        for raw in text.split(whereSeparator: \.isNewline) {
            let matches = raw.matches(of: stamp)
            guard let last = matches.last else { continue }
            let body = raw[last.range.upperBound...]
            let wordMatches = body.matches(of: wordStamp)
            var words: [LyricWord] = []
            for (index, match) in wordMatches.enumerated() {
                let textEnd = index + 1 < wordMatches.count ? wordMatches[index + 1].range.lowerBound : body.endIndex
                let segment = body[match.range.upperBound..<textEnd]
                let trimmed = segment.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let start = seconds(match.output.1, match.output.2)
                let end = index + 1 < wordMatches.count ? seconds(wordMatches[index + 1].output.1, wordMatches[index + 1].output.2) : start
                words.append(LyricWord(text: trimmed, start: start, end: end, spaceAfter: segment.last?.isWhitespace ?? true))
            }
            let display = body.replacing(wordStamp, with: "").trimmingCharacters(in: .whitespaces)
            for (index, match) in matches.enumerated() {
                // Word stamps belong to the first time the line is sung; repeats are line-timed.
                lines.append(Raw(time: seconds(match.output.1, match.output.2), text: display, words: index == 0 ? words : []))
            }
        }
        let sorted = lines.sorted { $0.time < $1.time }
        return finish(sorted.map { LyricLine(id: 0, time: $0.time, text: $0.text, words: $0.words) })
    }

    /// Number the lines in order, and fill in end times a provider left out:
    /// a word ends where the next starts, a line where the next line starts.
    static func finish(_ lines: [LyricLine]) -> [LyricLine] {
        let sorted = lines.sorted { $0.time < $1.time }
        return sorted.enumerated().map { index, line in
            var line = line
            line.id = index
            let nextLine = index + 1 < sorted.count ? sorted[index + 1].time : nil
            let fallbackEnd = nextLine.map { max($0, line.time) } ?? line.time + 5
            line.words = complete(line.words, lineEnd: line.end ?? fallbackEnd)
            line.background = complete(line.background, lineEnd: line.end ?? fallbackEnd)
            if line.end == nil {
                line.end = (line.words + line.background).map(\.end).max() ?? nextLine
            }
            return line
        }
    }

    private static func complete(_ words: [LyricWord], lineEnd: TimeInterval) -> [LyricWord] {
        let sorted = words.sorted { $0.start < $1.start }
        return sorted.enumerated().map { index, word in
            guard word.end <= word.start else { return word }
            var word = word
            let next = index + 1 < sorted.count ? sorted[index + 1].start : lineEnd
            word.end = word.start + min(max(next - word.start, 0.08), 10)
            return word
        }
    }

    /// Lead and duet by alternating singers; a group agent sings together. One singer is always lead.
    static func voices(for agents: [String?], groups: Set<String>) -> [LyricVoice] {
        var people: [String] = []
        for agent in agents.compactMap({ $0 }) where !groups.contains(agent) && !people.contains(agent) { people.append(agent) }
        guard people.count >= 2 else { return agents.map { _ in .lead } }
        return agents.map { agent in
            guard let agent else { return .lead }
            if groups.contains(agent) { return .together }
            return (people.firstIndex(of: agent) ?? 0) % 2 == 1 ? .duet : .lead
        }
    }
}
