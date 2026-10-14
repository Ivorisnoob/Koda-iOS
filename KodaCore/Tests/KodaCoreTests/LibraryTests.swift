import Foundation
import Testing
@testable import KodaCore

@MainActor
@Suite struct LibraryTests {
    func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "koda-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func survivesARelaunch() throws {
        let dir = try tempDirectory()
        let library = Library(directory: dir)
        let song = Song(id: "a", title: "A", artistLine: "X")
        library.toggleLike(song)
        library.recordPlay(song)
        library.toggleSave(AlbumSummary(id: "MPRE1", title: "Album", artistLine: "X"))
        library.recordSearch("weeknd")

        let reopened = Library(directory: dir)
        #expect(reopened.isLiked(song))
        #expect(reopened.recent.first?.id == "a")
        #expect(reopened.isSaved(album: "MPRE1"))
        #expect(reopened.searches == ["weeknd"])
    }

    @Test func recentKeepsOneEntryPerSongNewestFirst() {
        let library = Library(directory: nil)
        let a = Song(id: "a", title: "A", artistLine: ""), b = Song(id: "b", title: "B", artistLine: "")
        library.recordPlay(a)
        library.recordPlay(b)
        library.recordPlay(a)
        #expect(library.recent.map(\.id) == ["a", "b"])
    }

    @Test func searchHistoryIgnoresCaseDuplicatesAndBlanks() {
        let library = Library(directory: nil)
        library.recordSearch("Weeknd")
        library.recordSearch("  ")
        library.recordSearch("weeknd")
        #expect(library.searches == ["weeknd"])
    }

    @Test func toggleSaveTwiceRemoves() {
        let library = Library(directory: nil)
        let p = PlaylistSummary(id: "PL1", title: "P")
        library.toggleSave(p)
        library.toggleSave(p)
        #expect(!library.isSaved(playlist: "PL1"))
    }
}
