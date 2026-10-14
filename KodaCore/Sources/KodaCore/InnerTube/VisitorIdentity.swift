import Foundation

/// Koda's anonymous identity towards YouTube: the `visitorData` token.
///
/// YouTube's bot check keys on it. A `/player` call without one is refused,
/// and about one fresh token in ten is refused mid-stream: googlevideo serves
/// the opening ~1 MB and answers 403 past it. So there is one token per
/// install, kept for six hours, persisted across launches, and replaced the
/// moment it is refused. [verified October 2026]
actor VisitorIdentity {
    private let session: URLSession
    private let defaults: UserDefaults
    private let ttl: TimeInterval = 6 * 60 * 60

    private var token: String?
    private var mintedAt: Date?
    private var vetted: String?
    private var minting: Task<String?, Never>?

    /// - Parameter suite: a `UserDefaults` suite, so tests keep their own token.
    init(session: URLSession, suite: String?) {
        self.session = session
        let defaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        token = defaults.string(forKey: Keys.token)
        mintedAt = defaults.object(forKey: Keys.mintedAt) as? Date
        vetted = defaults.string(forKey: Keys.vetted)
    }

    /// The token without minting, for browse calls that must not wait on a mint.
    var cached: String? { token }

    /// The token to send, minting one when there is none or it has aged out.
    /// Nil only when a mint failed and nothing was ever stored.
    func current() async -> String? {
        if let token, let mintedAt, Date().timeIntervalSince(mintedAt) < ttl, mintedAt <= Date() {
            return token
        }
        return await mint() ?? token
    }

    /// Drop `refused` and mint a replacement. A caller that waited while
    /// another replaced the same token gets that replacement instead of a second mint.
    func replace(_ refused: String?) async -> String? {
        if let token, token != refused { return token }
        token = nil
        mintedAt = nil
        return await mint()
    }

    /// Whether googlevideo has been seen serving a whole stream under `token`.
    func isVetted(_ candidate: String) -> Bool { vetted == candidate }

    func markVetted(_ candidate: String) {
        vetted = candidate
        defaults.set(candidate, forKey: Keys.vetted)
    }

    private func mint() async -> String? {
        if let minting { return await minting.value }
        let task = Task { await Self.requestToken(session: session) }
        minting = task
        let fresh = await task.value
        minting = nil
        if let fresh {
            token = fresh
            mintedAt = Date()
            defaults.set(fresh, forKey: Keys.token)
            defaults.set(mintedAt, forKey: Keys.mintedAt)
        }
        return fresh
    }

    /// The `visitor_id` endpoint: a few hundred bytes, one round trip.
    private static func requestToken(session: URLSession) async -> String? {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Clients.browserUserAgent, forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["context": ["client": ["clientName": "WEB", "clientVersion": Clients.webVersion, "hl": "en", "gl": "US"]]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSON(data: data),
              let raw = json["responseContext"]["visitorData"].nonEmpty else { return nil }
        // The response URL-encodes the base64 padding; /player wants it raw.
        return raw.replacingOccurrences(of: "%3D", with: "=").replacingOccurrences(of: "%3d", with: "=")
    }

    private enum Keys {
        static let token = "koda.visitorData"
        static let mintedAt = "koda.visitorData.at"
        static let vetted = "koda.visitorData.vetted"
    }
}
