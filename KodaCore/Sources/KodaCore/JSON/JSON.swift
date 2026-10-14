import Foundation

/// A read-only view over a `JSONSerialization` tree.
///
/// InnerTube nests the same renderer at different depths across response
/// variants, so parsers walk the tree by key rather than decode fixed
/// `Codable` models. Every accessor is total: a missing key reads as `.null`.
public struct JSON: @unchecked Sendable {
    let raw: Any?

    public init(_ raw: Any?) { self.raw = raw }

    public init(data: Data) throws {
        raw = try JSONSerialization.jsonObject(with: data)
    }

    public static let null = JSON(nil)

    public subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    public subscript(index: Int) -> JSON {
        guard let array = raw as? [Any], array.indices.contains(index) else { return .null }
        return JSON(array[index])
    }

    public var exists: Bool { raw != nil && !(raw is NSNull) }
    public var isObject: Bool { raw is [String: Any] }
    public var string: String? { raw as? String }
    public var int: Int? { (raw as? NSNumber)?.intValue ?? (raw as? String).flatMap { Int($0) } }
    public var double: Double? { (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap { Double($0) } }
    public var bool: Bool? { (raw as? NSNumber)?.boolValue }
    public var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    public var keys: [String] { (raw as? [String: Any]).map { Array($0.keys) } ?? [] }

    /// A non-empty string, or nil.
    public var nonEmpty: String? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// The first key of an object, for renderer wrappers like `{ "musicTwoRowItemRenderer": {...} }`.
    public var firstKey: String? { (raw as? [String: Any])?.keys.first }

    /// Every object stored under `key` anywhere below this node, in document order.
    /// The search does not descend into a match, so nested renderers of the same kind are not repeated.
    public func objects(_ key: String) -> [JSON] {
        var out: [JSON] = []
        collect(raw, key, &out)
        return out
    }

    /// The first object under `key` anywhere below this node.
    public func first(_ key: String) -> JSON {
        objects(key).first ?? .null
    }

    /// Every string value stored under `key` anywhere below this node.
    public func strings(_ key: String) -> [String] {
        var out: [String] = []
        collectStrings(raw, key, &out)
        return out
    }

    private func collect(_ node: Any?, _ key: String, _ out: inout [JSON]) {
        if let dict = node as? [String: Any] {
            // Dictionary order is not document order; sort keys so results are deterministic.
            for k in dict.keys.sorted() {
                if k == key, dict[k] is [String: Any] { out.append(JSON(dict[k])) } else { collect(dict[k], key, &out) }
            }
        } else if let array = node as? [Any] {
            for element in array { collect(element, key, &out) }
        }
    }

    private func collectStrings(_ node: Any?, _ key: String, _ out: inout [String]) {
        if let dict = node as? [String: Any] {
            for k in dict.keys.sorted() {
                if k == key, let s = dict[k] as? String { out.append(s) } else { collectStrings(dict[k], key, &out) }
            }
        } else if let array = node as? [Any] {
            for element in array { collectStrings(element, key, &out) }
        }
    }
}

// MARK: - InnerTube text and images

extension JSON {
    /// The text runs of a formatted string.
    var runs: [JSON] { self["runs"].array }

    /// A formatted string's plain text: `simpleText`, or its runs joined.
    var text: String {
        if let simple = self["simpleText"].string { return simple }
        return runs.compactMap { $0["text"].string }.joined()
    }

    /// The widest image of the first `thumbnails` array found below this node.
    var bestThumbnail: Artwork? {
        guard let list = firstThumbnailList(raw) else { return nil }
        let best = list.map(JSON.init).max { ($0["width"].int ?? 0) < ($1["width"].int ?? 0) }
        guard let url = best?["url"].string.flatMap(URL.imageURL) else { return nil }
        return Artwork(url: url, width: best?["width"].int ?? 0, height: best?["height"].int ?? 0)
    }

    private func firstThumbnailList(_ node: Any?) -> [Any]? {
        if let dict = node as? [String: Any] {
            if let list = dict["thumbnails"] as? [Any], !list.isEmpty { return list }
            for k in dict.keys.sorted() where k != "overlay" {
                if let found = firstThumbnailList(dict[k]) { return found }
            }
        } else if let array = node as? [Any] {
            for element in array {
                if let found = firstThumbnailList(element) { return found }
            }
        }
        return nil
    }
}

extension URL {
    /// InnerTube image URLs, which are sometimes protocol-relative.
    static func imageURL(_ string: String) -> URL? {
        URL(string: string.hasPrefix("//") ? "https:" + string : string)
    }
}
