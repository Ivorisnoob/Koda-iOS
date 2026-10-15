import Foundation
import Testing
@testable import KodaCore

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

func songs(_ count: Int) -> [Song] {
    (0..<count).map { Song(id: "v\($0)", title: "Song \($0)", artistLine: "Artist") }
}

func ids(_ items: some Sequence<QueueItem>) -> [String] { items.map(\.song.id) }

@Suite struct PlayQueueTests {
    @Test func replaceStartsAtTheChosenSong() {
        var q = PlayQueue()
        q.replace(with: songs(5), startAt: 2)
        #expect(q.current?.song.id == "v2")
        #expect(ids(q.upcoming) == ["v3", "v4"])
        #expect(ids(q.history) == ["v0", "v1"])
    }

    @Test func outOfRangeStartIsClamped() {
        var q = PlayQueue()
        q.replace(with: songs(3), startAt: 9)
        #expect(q.current?.song.id == "v2")
        q.replace(with: songs(3), startAt: -4)
        #expect(q.current?.song.id == "v0")
    }

    @Test func emptyReplaceClearsButKeepsRepeat() {
        var q = PlayQueue()
        q.repeatMode = .all
        q.replace(with: songs(3))
        q.replace(with: [])
        #expect(q.isEmpty)
        #expect(q.current == nil)
        #expect(q.repeatMode == .all)
    }

    // MARK: Repeat

    @Test func endOfQueueStopsWithRepeatOff() {
        var q = PlayQueue()
        q.replace(with: songs(2), startAt: 1)
        let r1 = q.advance(automatic: true)
        #expect(r1 == nil)
        #expect(q.current?.song.id == "v1", "a failed advance leaves the queue where it was")
    }

    @Test func repeatAllWrapsBothWays() {
        var q = PlayQueue()
        q.repeatMode = .all
        q.replace(with: songs(3), startAt: 2)
        let r2 = q.advance(automatic: true)
        #expect(r2?.song.id == "v0")
        let r3 = q.retreat()
        #expect(r3?.song.id == "v2")
    }

    @Test func repeatOneRepeatsOnlyWhenTheSongEndsByItself() {
        var q = PlayQueue()
        q.repeatMode = .one
        q.replace(with: songs(3), startAt: 1)
        #expect(q.peekNext(automatic: true)?.song.id == "v1")
        let r4 = q.advance(automatic: true)
        #expect(r4?.song.id == "v1")
        let r5 = q.advance(automatic: false)
        #expect(r5?.song.id == "v2", "a skip moves on under repeat one")
        let r6 = q.advance(automatic: false)
        #expect(r6?.song.id == "v0", "and wraps at the end, like repeat all")
    }

    @Test func retreatAtStartStaysWithoutRepeat() {
        var q = PlayQueue()
        q.replace(with: songs(3))
        let r7 = q.retreat()
        #expect(r7?.song.id == "v0")
    }

    @Test func singleSongRepeatAllLoopsItself() {
        var q = PlayQueue()
        q.repeatMode = .all
        q.replace(with: songs(1))
        let r8 = q.advance(automatic: true)
        #expect(r8?.song.id == "v0")
        let r9 = q.retreat()
        #expect(r9?.song.id == "v0")
    }

    // MARK: Shuffle

    @Test func shuffleKeepsCurrentFirstAndEverySongOnce() {
        var rng = SeededGenerator(state: 7)
        var q = PlayQueue()
        q.replace(with: songs(20), startAt: 5, shuffled: false, using: &rng)
        q.setShuffle(true, using: &rng)
        #expect(q.current?.song.id == "v5")
        #expect(q.currentIndex == 0)
        #expect(Set(ids(q.items)) == Set(songs(20).map(\.id)))
        #expect(q.items.count == 20)
        #expect(ids(q.items) != songs(20).map(\.id))
    }

    @Test func unshuffleRestoresOrderAndKeepsCurrent() {
        var rng = SeededGenerator(state: 42)
        var q = PlayQueue()
        q.replace(with: songs(10), startAt: 3, shuffled: false, using: &rng)
        q.setShuffle(true, using: &rng)
        q.advance(automatic: false)
        q.advance(automatic: false)
        let playing = q.current
        q.setShuffle(false, using: &rng)
        #expect(ids(q.items) == songs(10).map(\.id))
        #expect(q.current == playing, "the song playing when shuffle goes off keeps playing")
    }

    @Test func shuffledStartPlaysTheTappedSongFirst() {
        var rng = SeededGenerator(state: 3)
        var q = PlayQueue()
        q.replace(with: songs(8), startAt: 4, shuffled: true, using: &rng)
        #expect(q.isShuffled)
        #expect(q.current?.song.id == "v4")
        #expect(q.history.isEmpty)
    }

    @Test func shuffleTwiceIsANoOp() {
        var rng = SeededGenerator(state: 9)
        var q = PlayQueue()
        q.replace(with: songs(6), startAt: 0, shuffled: true, using: &rng)
        let order = ids(q.items)
        q.setShuffle(true, using: &rng)
        #expect(ids(q.items) == order)
    }

    @Test func playNextWhileShuffledSurvivesUnshuffle() {
        var rng = SeededGenerator(state: 11)
        var q = PlayQueue()
        q.replace(with: songs(5), startAt: 1, shuffled: true, using: &rng)
        q.playNext([Song(id: "new", title: "New", artistLine: "")])
        #expect(q.upcoming.first?.song.id == "new")
        q.setShuffle(false, using: &rng)
        #expect(ids(q.items) == ["v0", "v1", "new", "v2", "v3", "v4"], "it stays right after the song it was queued behind")
    }

    @Test func appendWhileShuffledGoesToTheEndBothWays() {
        var rng = SeededGenerator(state: 5)
        var q = PlayQueue()
        q.replace(with: songs(4), startAt: 0, shuffled: true, using: &rng)
        q.append([Song(id: "tail", title: "Tail", artistLine: "")])
        #expect(q.items.last?.song.id == "tail")
        q.setShuffle(false, using: &rng)
        #expect(ids(q.items) == ["v0", "v1", "v2", "v3", "tail"])
    }

    @Test func removeWhileShuffledIsForgottenByUnshuffle() {
        var rng = SeededGenerator(state: 13)
        var q = PlayQueue()
        q.replace(with: songs(5), startAt: 0, shuffled: true, using: &rng)
        let victim = q.upcoming.first { $0.song.id == "v3" }!
        let r10 = q.remove(victim.id)
        #expect(r10)
        q.setShuffle(false, using: &rng)
        #expect(ids(q.items) == ["v0", "v1", "v2", "v4"])
    }

    // MARK: Editing

    @Test func duplicatesAreSeparateOccurrences() {
        var q = PlayQueue()
        let song = Song(id: "same", title: "Same", artistLine: "")
        q.replace(with: [song, song, song], startAt: 0)
        let second = q.items[1].id
        let r11 = q.remove(second)
        #expect(r11)
        #expect(q.items.count == 2)
        #expect(q.current?.id == q.items[0].id)
    }

    @Test func currentSongCannotBeRemoved() {
        var q = PlayQueue()
        q.replace(with: songs(3), startAt: 1)
        let r12 = q.remove(q.current!.id)
        #expect(!r12)
        #expect(q.items.count == 3)
    }

    @Test func removingFromHistoryKeepsTheSameSongCurrent() {
        var q = PlayQueue()
        q.replace(with: songs(5), startAt: 3)
        q.remove(q.items[0].id)
        #expect(q.current?.song.id == "v3")
        #expect(q.currentIndex == 2)
    }

    @Test func moveUpcomingUsesListOffsets() {
        var q = PlayQueue()
        q.replace(with: songs(6), startAt: 1)
        // Upcoming is v2 v3 v4 v5; drag v5 (offset 3) to the top (offset 0).
        q.moveUpcoming(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(ids(q.upcoming) == ["v5", "v2", "v3", "v4"])
        // Drag v5 (offset 0) below v3 (List passes destination 3).
        q.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(ids(q.upcoming) == ["v2", "v3", "v5", "v4"])
        #expect(q.current?.song.id == "v1")
    }

    @Test func playNextKeepsOrderOfSeveralSongs() {
        var q = PlayQueue()
        q.replace(with: songs(3), startAt: 0)
        q.playNext([Song(id: "a", title: "A", artistLine: ""), Song(id: "b", title: "B", artistLine: "")])
        #expect(ids(q.items) == ["v0", "a", "b", "v1", "v2"])
    }

    @Test func appendToEmptyQueueMakesTheFirstCurrent() {
        var q = PlayQueue()
        q.append(songs(2))
        #expect(q.current?.song.id == "v0")
    }

    @Test func clearUpcomingKeepsHistoryAndCurrent() {
        var rng = SeededGenerator(state: 2)
        var q = PlayQueue()
        q.replace(with: songs(5), startAt: 2, shuffled: false, using: &rng)
        q.clearUpcoming()
        #expect(ids(q.items) == ["v0", "v1", "v2"])
        q.setShuffle(true, using: &rng)
        q.setShuffle(false, using: &rng)
        #expect(ids(q.items) == ["v0", "v1", "v2"])
    }

    @Test func jumpChangesCurrentByOccurrence() {
        var q = PlayQueue()
        q.replace(with: songs(4), startAt: 0)
        let target = q.items[3].id
        let r13 = q.jump(to: target)
        #expect(r13)
        #expect(q.current?.id == target)
        let r14 = q.jump(to: UUID())
        #expect(!r14)
    }

    @Test func roundTripsThroughCodable() throws {
        var rng = SeededGenerator(state: 21)
        var q = PlayQueue()
        q.repeatMode = .one
        q.replace(with: songs(6), startAt: 2, shuffled: true, using: &rng)
        let data = try JSONEncoder().encode(q)
        var back = try JSONDecoder().decode(PlayQueue.self, from: data)
        #expect(back == q)
        back.setShuffle(false, using: &rng)
        #expect(ids(back.items) == songs(6).map(\.id))
    }
}

@Suite struct PlayQueueHistoryTests {
    private func songs(_ count: Int) -> [Song] {
        (0..<count).map { Song(id: "s\($0)", title: "\($0)", artistLine: "") }
    }

    @Test func trimsOnlyOldHistory() throws {
        var queue = PlayQueue()
        queue.replace(with: songs(10), startAt: 7)
        queue.trimHistory(keeping: 3)
        #expect(queue.items.map(\.song.id) == ["s4", "s5", "s6", "s7", "s8", "s9"])
        #expect(queue.current?.song.id == "s7")
        #expect(queue.history.count == 3)
        // Already within the limit: nothing changes.
        queue.trimHistory(keeping: 3)
        #expect(queue.items.count == 6)
    }

    @Test func trimmedShuffleStillUnshuffles() throws {
        var queue = PlayQueue()
        var rng = SeededGenerator(state: 7)
        queue.replace(with: songs(8), startAt: 0, shuffled: true, using: &rng)
        for _ in 0..<5 { queue.advance(automatic: false) }
        let current = try #require(queue.current?.song.id)
        queue.trimHistory(keeping: 2)
        queue.setShuffle(false)
        #expect(queue.current?.song.id == current)
        #expect(Set(queue.items.map(\.song.id)).count == queue.items.count)
        #expect(queue.items.count == 5)
    }
}
