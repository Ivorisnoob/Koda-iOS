import Foundation

extension Lyrics {
    /// Apple-style TTML: `<p begin end ttm:agent>` lines of `<span begin end>` words, the
    /// whitespace between spans marking word breaks, and backing vocals in a
    /// `<span ttm:role="x-bg">` of their own. Line-timed TTML (no word spans) works too.
    public static func parseTTML(_ text: String) -> [LyricLine]? {
        guard let data = text.data(using: .utf8) else { return nil }
        let reader = TTMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = reader
        guard parser.parse() || !reader.lines.isEmpty else { return nil }
        let voices = voices(for: reader.agents, groups: reader.groupAgents)
        var lines = reader.lines
        for index in lines.indices { lines[index].voice = voices[index] }
        let finished = finish(lines.filter { !$0.text.isEmpty })
        return finished.isEmpty ? nil : finished
    }

    /// YouLyPlus's own JSON: `lyrics[]` of `{time, duration, text, syllabus[], element.singer}`, times in milliseconds.
    static func parseYouLyPlus(_ json: JSON) -> [LyricLine]? {
        let items = json["lyrics"].array
        guard !items.isEmpty else { return nil }
        var groups = Set<String>()
        let agents = json["metadata"]["agents"]
        for key in agents.keys where agents[key]["type"].string?.lowercased() == "group" { groups.insert(key) }

        var lines: [LyricLine] = []
        var singers: [String?] = []
        for item in items {
            guard let time = item["time"].double else { continue }
            var words: [LyricWord] = [], background: [LyricWord] = []
            for syllable in item["syllabus"].array {
                guard let raw = syllable["text"].string, let start = syllable["time"].double else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let duration = syllable["duration"].double ?? 0
                let word = LyricWord(text: trimmed, start: start / 1000, end: (start + duration) / 1000,
                                     spaceAfter: raw.last?.isWhitespace ?? false)
                if syllable["isBackground"].bool == true { background.append(word) } else { words.append(word) }
            }
            // A syllable that ends a line has no space after it to say so; the line break is one.
            if !words.isEmpty { words[words.count - 1].spaceAfter = true }
            if !background.isEmpty { background[background.count - 1].spaceAfter = true }
            let text = words.isEmpty ? (item["text"].nonEmpty ?? "") : joined(words)
            guard !text.isEmpty else { continue }
            let duration = item["duration"].double ?? 0
            lines.append(LyricLine(id: 0, time: time / 1000, text: text, words: words, background: background,
                                   end: duration > 0 ? (time + duration) / 1000 : nil))
            singers.append(item["element"]["singer"].string)
        }
        let voices = voices(for: singers, groups: groups)
        for index in lines.indices { lines[index].voice = voices[index] }
        let finished = finish(lines)
        return finished.isEmpty ? nil : finished
    }

    /// Whatever a provider sent, as lyrics: TTML, LRC (plain or enhanced), or plain text.
    static func parseAny(_ text: String) -> Lyrics? {
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("<"), cleaned.contains("<tt") || cleaned.contains("www.w3.org/ns/ttml") {
            return parseTTML(cleaned).map(Lyrics.synced)
        }
        if cleaned.hasPrefix("<") || cleaned.hasPrefix("{") { return nil }
        let synced = parseLRC(cleaned)
        if !synced.isEmpty { return .synced(synced) }
        return .plain(cleaned)
    }

    static func joined(_ words: [LyricWord]) -> String {
        var out = ""
        for word in words {
            out += word.text
            if word.spaceAfter { out += " " }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// `27.395`, `2:19.610`, `1:02:03.5`, `12.3s`, `500ms`, `1.5m`; nil for anything else.
    static func ttmlTime(_ value: String) -> TimeInterval? {
        let time = value.trimmingCharacters(in: .whitespaces)
        if time.hasSuffix("ms") { return Double(time.dropLast(2)).map { $0 / 1000 } }
        if time.hasSuffix("s") { return Double(time.dropLast()) }
        if time.hasSuffix("m") { return Double(time.dropLast()).map { $0 * 60 } }
        if time.hasSuffix("h") { return Double(time.dropLast()).map { $0 * 3600 } }
        let parts = time.split(separator: ":").map { Double($0) }
        guard !parts.contains(where: { $0 == nil }) else { return nil }
        let numbers = parts.compactMap { $0 }
        switch numbers.count {
        case 1: return numbers[0]
        case 2: return numbers[0] * 60 + numbers[1]
        case 3: return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default: return nil
        }
    }
}

/// Walks a TTML document into lines. Names are matched without their prefix, so
/// `tt:p` and `p` read alike.
private final class TTMLReader: NSObject, XMLParserDelegate {
    var lines: [LyricLine] = []
    var agents: [String?] = []
    var groupAgents = Set<String>()

    private struct Span {
        var begin: TimeInterval?
        var end: TimeInterval?
        var isBackground: Bool
        var text = ""
    }

    private var inLine = false
    private var lineStart: TimeInterval = 0
    private var lineEnd: TimeInterval?
    private var lineAgent: String?
    private var lineText = ""
    private var spans: [Span] = []
    private var words: [LyricWord] = []
    private var background: [LyricWord] = []

    private func local(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name))
    }

    private func attribute(_ attributes: [String: String], _ suffix: String) -> String? {
        attributes.first { local($0.key) == suffix }?.value
    }

    private func times(_ attributes: [String: String], start: TimeInterval?) -> (TimeInterval?, TimeInterval?) {
        let begin = attribute(attributes, "begin").flatMap(Lyrics.ttmlTime)
        var end = attribute(attributes, "end").flatMap(Lyrics.ttmlTime)
        if end == nil, let dur = attribute(attributes, "dur").flatMap(Lyrics.ttmlTime), let from = begin ?? start {
            end = from + dur
        }
        return (begin, end)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch local(elementName) {
        case "agent":
            if attribute(attributes, "type")?.lowercased() == "group", let id = attribute(attributes, "id") {
                groupAgents.insert(id)
            }
        case "p":
            let (begin, end) = times(attributes, start: nil)
            guard let begin else { return }
            inLine = true
            lineStart = begin
            lineEnd = end
            lineAgent = attribute(attributes, "agent")
            lineText = ""
            spans = []
            words = []
            background = []
        case "span" where inLine:
            let (begin, end) = times(attributes, start: spans.last?.begin ?? lineStart)
            let isBackground = attribute(attributes, "role") == "x-bg" || (spans.last?.isBackground ?? false)
            spans.append(Span(begin: begin, end: end, isBackground: isBackground))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inLine else { return }
        if let index = spans.indices.last, spans[index].begin != nil {
            spans[index].text += string
        } else if string.contains(where: \.isWhitespace), string.allSatisfy(\.isWhitespace) {
            // Whitespace between word spans is the only sign that one word ended and the next began.
            let inBackground = spans.last?.isBackground ?? false
            if inBackground, !background.isEmpty {
                background[background.count - 1].spaceAfter = true
            } else if !inBackground, !words.isEmpty {
                words[words.count - 1].spaceAfter = true
            }
            lineText += " "
        } else {
            lineText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch local(elementName) {
        case "span" where inLine:
            guard let span = spans.popLast() else { return }
            guard let begin = span.begin else { return }
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // Some files time words from the start of their line rather than of the song.
            let lineLength = (lineEnd ?? lineStart + 30) - lineStart
            let relative = begin < lineStart - 0.25 && begin <= lineLength + 1
            let start = relative ? lineStart + begin : begin
            let end = span.end.map { relative ? lineStart + $0 : $0 } ?? start
            let word = LyricWord(text: trimmed, start: start, end: end, spaceAfter: span.text.last?.isWhitespace ?? false)
            if span.isBackground { background.append(word) } else { words.append(word) }
        case "p" where inLine:
            inLine = false
            if !words.isEmpty { words[words.count - 1].spaceAfter = true }
            if !background.isEmpty { background[background.count - 1].spaceAfter = true }
            let text = words.isEmpty
                ? lineText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                : Lyrics.joined(words)
            lines.append(LyricLine(id: 0, time: lineStart, text: text, words: words, background: background, end: lineEnd))
            agents.append(lineAgent)
        default:
            break
        }
    }
}
