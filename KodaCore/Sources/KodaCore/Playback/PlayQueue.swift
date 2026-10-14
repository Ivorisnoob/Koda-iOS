import Foundation

/// One occurrence of a song in the queue. The same song can be queued twice,
/// so anything planned across a suspension (preloading, a retry, a skip)
/// anchors on this id, never on an index or the video id.
public struct QueueItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var song: Song

    public init(song: Song, id: UUID = UUID()) {
        self.id = id
        self.song = song
    }
}

public enum RepeatMode: String, Codable, Sendable, CaseIterable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// The play queue: what plays now, what came before and what comes next.
///
/// `items` is always the order playback follows, so a queue screen draws it
/// as is. Shuffle reorders `items` and remembers the order it replaced; turning
/// shuffle off puts that order back with the current song still current.
public struct PlayQueue: Codable, Sendable, Equatable {
    public private(set) var items: [QueueItem] = []
    public private(set) var currentIndex: Int?
    public private(set) var isShuffled = false
    public var repeatMode: RepeatMode = .off
    /// The order before shuffle, by occurrence. Empty while not shuffled.
    private var unshuffledOrder: [UUID] = []

    public init() {}

    public var current: QueueItem? { currentIndex.map { items[$0] } }
    public var isEmpty: Bool { items.isEmpty }

    /// What plays after the current song, in order.
    public var upcoming: ArraySlice<QueueItem> {
        guard let currentIndex else { return items[...] }
        return items[(currentIndex + 1)...]
    }

    /// What already played, oldest first.
    public var history: ArraySlice<QueueItem> {
        guard let currentIndex else { return [] }
        return items[..<currentIndex]
    }

    // MARK: Replacing

    /// Play `songs` starting at `startIndex`; shuffled, the start song plays first and the rest follow in random order.
    public mutating func replace(with songs: [Song], startAt startIndex: Int = 0, shuffled: Bool = false) {
        var rng = SystemRandomNumberGenerator()
        replace(with: songs, startAt: startIndex, shuffled: shuffled, using: &rng)
    }

    public mutating func replace<R: RandomNumberGenerator>(with songs: [Song], startAt startIndex: Int, shuffled: Bool, using rng: inout R) {
        let fresh = songs.map { QueueItem(song: $0) }
        guard !fresh.isEmpty else {
            self = PlayQueue(repeatMode: repeatMode)
            return
        }
        let start = min(max(startIndex, 0), fresh.count - 1)
        items = fresh
        currentIndex = start
        isShuffled = false
        unshuffledOrder = []
        if shuffled { setShuffle(true, using: &rng) }
    }

    private init(repeatMode: RepeatMode) {
        self.repeatMode = repeatMode
    }

    public mutating func clear() {
        self = PlayQueue(repeatMode: repeatMode)
    }

    // MARK: Adding and removing

    /// Insert right after the current song, in the order given.
    public mutating func playNext(_ songs: [Song]) {
        let added = songs.map { QueueItem(song: $0) }
        guard !added.isEmpty else { return }
        guard let currentIndex else {
            append(songs)
            return
        }
        items.insert(contentsOf: added, at: currentIndex + 1)
        if isShuffled, let anchor = unshuffledOrder.firstIndex(of: items[currentIndex].id) {
            unshuffledOrder.insert(contentsOf: added.map(\.id), at: anchor + 1)
        }
    }

    /// Add to the end of the queue.
    public mutating func append(_ songs: [Song]) {
        let added = songs.map { QueueItem(song: $0) }
        items += added
        if isShuffled { unshuffledOrder += added.map(\.id) }
        if currentIndex == nil, !items.isEmpty { currentIndex = 0 }
    }

    /// Remove an occurrence. The current song cannot be removed this way; skip it instead.
    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), index != currentIndex else { return false }
        items.remove(at: index)
        unshuffledOrder.removeAll { $0 == id }
        if let currentIndex, index < currentIndex { self.currentIndex = currentIndex - 1 }
        return true
    }

    /// Drop everything after the current song.
    public mutating func clearUpcoming() {
        guard let currentIndex else {
            clear()
            return
        }
        let dropped = Set(items[(currentIndex + 1)...].map(\.id))
        items.removeSubrange((currentIndex + 1)...)
        unshuffledOrder.removeAll { dropped.contains($0) }
    }

    /// Reorder within the upcoming songs; offsets count from the first upcoming song, as a list of them does.
    public mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (currentIndex ?? -1) + 1
        var upcoming = Array(items[base...])
        let valid = source.filter { upcoming.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { upcoming[$0] }
        let insertAt = min(max(destination, 0), upcoming.count) - valid.filter { $0 < destination }.count
        for index in valid.reversed() { upcoming.remove(at: index) }
        upcoming.insert(contentsOf: moving, at: insertAt)
        items.replaceSubrange(base..., with: upcoming)
    }

    // MARK: Moving through the queue

    /// Make `id` the current song.
    @discardableResult
    public mutating func jump(to id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        currentIndex = index
        return true
    }

    /// The index that would play next. A song ending on its own repeats under
    /// repeat one; a skip always moves on.
    public func nextIndex(automatic: Bool) -> Int? {
        guard let currentIndex else { return items.isEmpty ? nil : 0 }
        if automatic, repeatMode == .one { return currentIndex }
        if currentIndex + 1 < items.count { return currentIndex + 1 }
        return repeatMode == .off ? nil : 0
    }

    public func peekNext(automatic: Bool) -> QueueItem? {
        nextIndex(automatic: automatic).map { items[$0] }
    }

    /// Move to the next song; nil at the end of a queue that does not repeat, and the queue is left unchanged.
    @discardableResult
    public mutating func advance(automatic: Bool) -> QueueItem? {
        guard let next = nextIndex(automatic: automatic) else { return nil }
        currentIndex = next
        return items[next]
    }

    /// Move to the previous song; at the start it wraps under repeat all and otherwise stays.
    @discardableResult
    public mutating func retreat() -> QueueItem? {
        guard let currentIndex else { return nil }
        if currentIndex > 0 {
            self.currentIndex = currentIndex - 1
        } else if repeatMode != .off, items.count > 1 {
            self.currentIndex = items.count - 1
        }
        return current
    }

    // MARK: Shuffle

    public mutating func setShuffle(_ on: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(on, using: &rng)
    }

    /// On: the current song stays current and every other song follows in random order.
    /// Off: the order from before shuffle comes back, songs added meanwhile kept where they were added.
    public mutating func setShuffle<R: RandomNumberGenerator>(_ on: Bool, using rng: inout R) {
        guard on != isShuffled else { return }
        if on {
            unshuffledOrder = items.map(\.id)
            guard let currentIndex else {
                items.shuffle(using: &rng)
                isShuffled = true
                return
            }
            let current = items[currentIndex]
            var rest = items
            rest.remove(at: currentIndex)
            rest.shuffle(using: &rng)
            items = [current] + rest
            self.currentIndex = 0
        } else {
            let currentId = current?.id
            let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            var restored = unshuffledOrder.compactMap { byId[$0] }
            // Anything the shuffled order gained that the old order never saw goes at the end.
            let known = Set(unshuffledOrder)
            restored += items.filter { !known.contains($0.id) }
            items = restored
            currentIndex = currentId.flatMap { id in items.firstIndex { $0.id == id } } ?? (items.isEmpty ? nil : 0)
            unshuffledOrder = []
        }
        isShuffled = on
    }
}
