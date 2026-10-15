import Foundation

// Stand-in content for loading screens. A page draws these through its real layout,
// redacted, so the placeholder has the loaded page's exact geometry and nothing moves
// when the real content replaces it. The text only sets the shape of each line.

extension Song {
    private static let placeholderTitles = ["Song title here", "A longer song title", "Title", "Another song name", "Short one", "Song title"]

    public static func placeholder(_ index: Int) -> Song {
        Song(id: "placeholder-\(index)",
             title: placeholderTitles[index % placeholderTitles.count],
             artistLine: index.isMultiple(of: 2) ? "Artist name" : "Artist",
             duration: 200)
    }

    public static func placeholders(_ count: Int) -> [Song] { (0..<count).map(placeholder) }

    public var isPlaceholder: Bool { id.hasPrefix("placeholder-") }
}

extension AlbumSummary {
    public static func placeholder(_ index: Int) -> AlbumSummary {
        AlbumSummary(id: "placeholder-\(index)", title: "Album title", artistLine: "Artist", year: 2024, kind: .album)
    }
}

extension AlbumPage {
    public static func placeholder(_ album: AlbumSummary) -> AlbumPage {
        AlbumPage(album: album, description: nil, detailLine: nil, songs: Song.placeholders(10),
                  otherVersions: [], audioPlaylistId: nil)
    }
}

extension PlaylistPage {
    public static func placeholder(_ playlist: PlaylistSummary) -> PlaylistPage {
        PlaylistPage(playlist: playlist, author: nil, detailLine: nil, description: nil, songs: Song.placeholders(10), continuation: nil)
    }
}

extension ArtistPage {
    public static func placeholder(_ artist: ArtistSummary) -> ArtistPage {
        ArtistPage(artist: artist, description: nil, banner: nil, topSongs: Song.placeholders(5), allSongsPlaylistId: nil,
                   albums: (0..<4).map(AlbumSummary.placeholder), singles: [], featuredOn: [], similar: [])
    }
}
