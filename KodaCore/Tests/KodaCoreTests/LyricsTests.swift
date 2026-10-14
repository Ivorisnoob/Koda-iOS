import Foundation
import Testing
@testable import KodaCore

@Suite struct LyricsTests {
    @Test func parsesStampsAndRepeatedLines() {
        let lines = Lyrics.parseLRC("""
        [ar:Someone]
        [00:13.13] Yeah
        [00:27.16] I've been tryna call
        [01:02.50][02:10.00] Chorus
        not a lyric
        """)
        #expect(lines.map(\.text) == ["Yeah", "I've been tryna call", "Chorus", "Chorus"])
        #expect(lines[0].time == 13.13)
        #expect(lines[3].time == 130)
        #expect(lines.map(\.id) == [0, 1, 2, 3])
    }

    @Test func findsTheLineThatHasStarted() {
        let lines = Lyrics.parseLRC("[00:10.00] a\n[00:20.00] b\n[00:30.00] c")
        #expect(Lyrics.index(of: 5, in: lines) == nil)
        #expect(Lyrics.index(of: 10, in: lines) == 0)
        #expect(Lyrics.index(of: 29.9, in: lines) == 1)
        #expect(Lyrics.index(of: 500, in: lines) == 2)
    }
}
