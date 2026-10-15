import KodaCore
import SwiftUI

/// Home on the Mac. The first screenful does the work: Your Mix beside Quick picks, so there
/// is something to play the moment the window opens, then what the listener goes back to,
/// then YouTube Music's shelves, each a row of covers that pages with its arrows.
struct MacHomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var model = HomeModel()
    @State private var width: CGFloat = 1000

    var body: some View {
        MacPage {
            header
            switch model.state {
            case .loading:
                sections(.placeholder)
                    .loadingPlaceholder()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Load Home", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            case .loaded(let content):
                sections(content)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.smooth, value: model.state.value == nil)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh Home (⌘R)")
            }
        }
        .task { if model.state.value == nil { await load() } }
    }

    private var header: some View {
        MacPageTitle(title: greeting, subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
    }

    @ViewBuilder
    private func sections(_ content: HomeModel.Content) -> some View {
        top(content)

        let jump = JumpBackIn.items(in: library)
        if jump.count >= 2 {
            MacShelf(title: "Jump back in") {
                ForEach(jump) { item in
                    NavigationLink(value: JumpBackIn.route(item)) {
                        MacCoverCard(title: JumpBackIn.title(item), subtitle: JumpBackIn.subtitle(item)) {
                            JumpBackIn.cover(item, size: MacMetrics.card)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !library.recent.isEmpty {
            MacShelf(title: "Recently played", seeAll: .songs(title: "Recently Played", source: .recent)) {
                ForEach(Array(library.recent.prefix(16).enumerated()), id: \.element.id) { index, song in
                    Button { player.play(Array(library.recent.prefix(50)), startAt: index) } label: {
                        MacCoverCard(artwork: song.artwork, title: song.title, subtitle: song.artistLine,
                                     onPlay: { player.play(Array(library.recent.prefix(50)), startAt: index) })
                    }
                    .buttonStyle(.plain)
                    .contextMenu { SongMenuItems(song: song) }
                }
            }
        }
        if let first = content.shelves.first {
            MacItemShelf(shelf: first)
        }
        let yours = model.topArtists(library)
        if yours.count >= 3 {
            MacShelf(title: "Your top artists", subtitle: "Based on your listening") {
                ForEach(yours, id: \.name) { ref in
                    if let id = ref.id {
                        MacArtistCard(artist: ArtistSummary(id: id, name: ref.name, artwork: model.artistPhotos[id]))
                    }
                }
            }
        }
        if let releases = content.newReleases {
            MacItemShelf(shelf: releases)
        }
        ForEach(content.shelves.dropFirst()) { shelf in
            MacItemShelf(shelf: shelf)
        }
        if !content.chartArtists.isEmpty {
            MacShelf(title: "Top artists", subtitle: "Charts") {
                ForEach(content.chartArtists) { artist in
                    MacArtistCard(artist: artist)
                }
            }
        }
    }

    /// Your Mix and Quick picks side by side; stacked when the window is too narrow for both.
    @ViewBuilder
    private func top(_ content: HomeModel.Content) -> some View {
        let picks = Array(content.quickPicks.prefix(width > 1180 ? 12 : 8))
        let layout = width > 900
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 28))
        layout {
            mix
                .frame(width: width > 900 ? 380 : nil)
                .frame(maxWidth: width > 900 ? nil : 520, alignment: .leading)
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    MacSectionTitle(title: content.quickPicksTitle, subtitle: library.recent.isEmpty ? "Trending now" : "Start with these")
                        .padding(.leading, 6)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 8, alignment: .top)], spacing: 2) {
                        ForEach(Array(picks.enumerated()), id: \.offset) { index, song in
                            MacSongTile(song: song) { player.play(content.quickPicks, startAt: index) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, MacMetrics.gutter)
    }

    @ViewBuilder
    private var mix: some View {
        if let mix = model.mix {
            MixHero(mix: mix)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if model.mixPending {
            MixHero(mix: .placeholder)
                .loadingPlaceholder()
        }
    }

    private func load() async {
        await model.load(music: app.music, library: library)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Up late"
        }
    }
}
