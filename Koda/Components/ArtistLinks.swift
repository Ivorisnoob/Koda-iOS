import KodaCore
import SwiftUI

extension Song {
    /// The artists YouTube linked, once each, in credit order.
    var linkedArtists: [ArtistRef] { ArtistRef.linked(artists) }
}

extension ArtistRef {
    /// Only the artists that can be opened, without repeats. Names are never split on
    /// "&" or ","; "She & Him" is one artist, and only YouTube's links tell them apart.
    static func linked(_ refs: [ArtistRef]) -> [ArtistRef] {
        var seen = Set<String>()
        return refs.filter { ref in
            guard let id = ref.id else { return false }
            return seen.insert(id).inserted
        }
    }
}

/// A byline that opens its artist: straight to the page for one artist, a menu
/// to choose from for several, plain text when none can be opened.
struct ArtistLinks<Label: View>: View {
    let line: String
    let artists: [ArtistRef]
    let open: (ArtistSummary) -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        let linked = ArtistRef.linked(artists)
        switch linked.count {
        case 0:
            label()
        case 1:
            Button { open(ArtistSummary(id: linked[0].id!, name: linked[0].name)) } label: { label() }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(linked[0].name)")
        default:
            Menu {
                Section("Artists") {
                    ForEach(linked, id: \.id) { artist in
                        Button(artist.name, systemImage: "music.mic") { open(ArtistSummary(id: artist.id!, name: artist.name)) }
                    }
                }
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose an artist to open")
        }
    }
}

/// "Go to Artist" for a song's menu: one button, or a submenu when several artists sing it.
struct GoToArtistItems: View {
    let song: Song
    let open: (ArtistSummary) -> Void

    var body: some View {
        let linked = song.linkedArtists
        if linked.count == 1 {
            Button("Go to Artist", systemImage: "music.mic") { open(ArtistSummary(id: linked[0].id!, name: linked[0].name)) }
        } else if linked.count > 1 {
            Menu("Go to Artist", systemImage: "music.mic") {
                ForEach(linked, id: \.id) { artist in
                    Button(artist.name) { open(ArtistSummary(id: artist.id!, name: artist.name)) }
                }
            }
        }
    }
}
