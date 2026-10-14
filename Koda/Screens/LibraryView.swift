import KodaCore
import SwiftUI

/// What the listener saved on this phone.
struct LibraryView: View {
    @Environment(Library.self) private var library

    private var isEmpty: Bool {
        library.liked.isEmpty && library.albums.isEmpty && library.playlists.isEmpty && library.artists.isEmpty && library.recent.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 0) {
                    LibraryLink(title: "Liked Songs", systemImage: "heart.fill", count: library.liked.count,
                                route: .songs(title: "Liked Songs", source: .liked))
                    Divider().padding(.leading, 56)
                    LibraryLink(title: "Recently Played", systemImage: "clock.fill", count: library.recent.count,
                                route: .songs(title: "Recently Played", source: .recent))
                }
                .padding(.horizontal, 20)

                if !library.playlists.isEmpty {
                    grid("Playlists", items: library.playlists.map(MusicItem.playlist))
                }
                if !library.albums.isEmpty {
                    grid("Albums", items: library.albums.map(MusicItem.album))
                }
                if !library.artists.isEmpty {
                    ShelfView(title: "Artists") {
                        ForEach(library.artists) { artist in
                            NavigationLink(value: Route.artist(artist)) { ArtistCard(artist: artist, width: 100) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if isEmpty {
                    ContentUnavailableView("Your Library Is Empty", systemImage: "square.stack",
                                           description: Text("Like songs, and add albums, playlists and artists with the + button on their pages."))
                        .padding(.top, 40)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Library")
    }

    private func grid(_ title: String, items: [MusicItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)], spacing: 20) {
                ForEach(items) { item in
                    if let route = Route(item) {
                        NavigationLink(value: route) {
                            GeometryReader { geometry in
                                CoverCard(artwork: item.artwork, title: item.title, subtitle: subtitle(item), width: geometry.size.width)
                            }
                            .aspectRatio(0.78, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func subtitle(_ item: MusicItem) -> String? {
        switch item {
        case .album(let a): a.cardSubtitle
        case .playlist(let p): p.subtitle
        default: nil
        }
    }
}

private struct LibraryLink: View {
    let title: String
    let systemImage: String
    let count: Int
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                Text(title).font(.body)
                Spacer()
                if count > 0 {
                    Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
