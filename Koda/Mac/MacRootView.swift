import KodaCore
import SwiftUI

/// A place in the Mac's sidebar.
enum MacSection: Hashable {
    case home, browse, search
    case recent, liked, albums, playlists, artists, downloads, stats
    case lastFM
    case userPlaylist(UUID)
}

/// Koda on the Mac: a sidebar of everything there is to go to, the page on the right, and the
/// player bar under it. The pages inside are the Mac's own; the models and menus are the phone's.
struct MacRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(Downloads.self) private var downloads
    @State private var section: MacSection? = .home
    @State private var path: [Route] = []
    @State private var search = SearchModel()
    @FocusState private var searchFocused: Bool
    @State private var showsNowPlaying = false
    @State private var namingPlaylist = false
    @State private var draftName = ""
    @State private var renaming: UserPlaylist?
    @State private var deleting: UserPlaylist?

    var body: some View {
        @Bindable var model = model
        @Bindable var search = search
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 320)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .routeDestinations()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    MacPlayerBar { panel in
                        model.requestedPanel = panel
                        showsNowPlaying = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.35), value: player.current == nil)
        }
        .searchable(text: $search.query, placement: .sidebar, prompt: "Songs, artists, albums or a link")
        .searchFocused($searchFocused)
        .searchSuggestions {
            if search.query != search.submitted {
                if let link = YouTubeLink(text: search.query) {
                    Label(link.openTitle, systemImage: "link").searchCompletion(search.query)
                }
                ForEach(search.suggestions, id: \.self) { suggestion in
                    Label(suggestion, systemImage: "magnifyingglass").searchCompletion(suggestion)
                }
            }
        }
        .onSubmit(of: .search) { submit(search.query) }
        .onChange(of: search.query) { _, text in
            if text.isEmpty {
                search.clear()
                if section == .search { section = .browse }
            }
        }
        .task(id: search.query) { await search.suggest(music: model.music) }
        .onChange(of: section) { _, _ in path = [] }
        .onChange(of: model.selectedTab) { _, tab in
            switch tab {
            case .home: section = .home
            case .library: section = .recent
            case .search:
                if section != .search { section = .browse }
                searchFocused = true
            }
        }
        .onChange(of: model.requestedMacSection) { _, requested in
            guard let requested else { return }
            model.requestedMacSection = nil
            section = requested
        }
        .onChange(of: model.pendingRoute) { _, route in
            guard let route else { return }
            model.pendingRoute = nil
            path.append(route)
        }
        .fullScreenCover(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .appEnvironment(model)
        }
        .onChange(of: model.isNowPlayingPresented) { _, shown in showsNowPlaying = shown }
        .onChange(of: showsNowPlaying) { _, shown in model.isNowPlayingPresented = shown }
        .task(id: player.current?.artwork) { await model.nowPlayingPalette.load(player.current?.artwork) }
        .playlistPicker(whenOnTop: !showsNowPlaying)
        .sheet(isPresented: $model.isProfilePresented) {
            ProfileView()
                .appEnvironment(model)
                .frame(minWidth: 540, idealWidth: 600, minHeight: 640, idealHeight: 760)
        }
        .onOpenURL { url in
            if !model.open(url) { model.linkError = "Koda can open YouTube Music songs, albums, playlists and artists." }
        }
        .alert("Couldn't Open Link", isPresented: Binding(get: { model.linkError != nil }, set: { if !$0 { model.linkError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.linkError ?? "")
        }
        .alert("New Playlist", isPresented: $namingPlaylist) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { section = .userPlaylist(library.createPlaylist(named: draftName).id) }
        } message: {
            Text("Add songs to it from any song's menu.")
        }
        .alert("Rename Playlist", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let renaming { library.renamePlaylist(renaming.id, to: draftName) } }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                guard let deleting else { return }
                if section == .userPlaylist(deleting.id) { section = .home }
                library.deletePlaylist(deleting.id)
            }
        } message: {
            Text("The songs stay wherever else you saved them.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            Section {
                sidebarRow("Home", "house", .home)
                sidebarRow("Browse", "square.grid.2x2", .browse)
                if search.submitted != nil {
                    sidebarRow("Search Results", "magnifyingglass", .search)
                }
            }
            Section("Library") {
                sidebarRow("Recently Played", "clock", .recent)
                sidebarRow("Liked Songs", "heart", .liked, count: library.liked.count)
                sidebarRow("Albums", "square.stack", .albums)
                sidebarRow("Playlists", "music.note.list", .playlists)
                sidebarRow("Artists", "music.mic", .artists)
                sidebarRow("Downloads", "arrow.down.circle", .downloads, count: downloads.songs.count)
                sidebarRow("Listening Stats", "chart.bar", .stats)
                sidebarRow("Last.fm", "dot.radiowaves.left.and.right", .lastFM)
            }
            Section {
                ForEach(library.userPlaylists) { playlist in
                    sidebarRow(playlist.name, "music.note", .userPlaylist(playlist.id))
                        .contextMenu {
                            Button("Play", systemImage: "play") { player.play(playlist.songs) }
                                .disabled(playlist.songs.isEmpty)
                            Button("Rename…", systemImage: "pencil") {
                                draftName = playlist.name
                                renaming = playlist
                            }
                            Divider()
                            Button("Delete Playlist…", systemImage: "trash", role: .destructive) { deleting = playlist }
                        }
                }
                Button {
                    draftName = ""
                    namingPlaylist = true
                } label: {
                    MacSidebarLabel(title: "New Playlist", systemImage: "plus", isSelected: false, dimmed: true)
                }
                .buttonStyle(.plain)
                .listRowInsets(MacSidebarLabel.insets)
                .listRowBackground(Color.clear)
            } header: {
                Text("Your Playlists")
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 28)
        .safeAreaInset(edge: .bottom, spacing: 0) { profileButton }
    }

    /// A Mac sidebar row: 13-point text, the symbol in the accent colour, and when selected the
    /// soft rounded fill the Mac's own sidebars use, rather than Catalyst's iPad-sized row.
    private func sidebarRow(_ title: String, _ systemImage: String, _ target: MacSection, count: Int = 0) -> some View {
        Button { section = target } label: {
            MacSidebarLabel(title: title, systemImage: systemImage, isSelected: section == target, count: count)
        }
        .buttonStyle(.plain)
        .listRowInsets(MacSidebarLabel.insets)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(section == target ? .isSelected : [])
    }

    /// The listener, at the foot of the sidebar: their profile, stats and Settings.
    private var profileButton: some View {
        Button { model.isProfilePresented = true } label: {
            HStack(spacing: 10) {
                AvatarView(size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.profile.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("Profile & Settings").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .contentShape(.rect)
        }
        .buttonStyle(MacSidebarButtonStyle())
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .help("Profile and Settings (⌘,)")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch section ?? .home {
        case .home: MacHomeView()
        case .browse: MacBrowseView(search: search) { submit($0) }
        case .search: MacSearchResultsView(model: search)
        case .recent: SavedSongsView(title: "Recently Played", source: .recent)
        case .liked: SavedSongsView(title: "Liked Songs", source: .liked)
        case .downloads: SavedSongsView(title: "Downloads", source: .downloaded)
        case .albums: MacLibraryGrid(kind: .albums)
        case .playlists: MacLibraryGrid(kind: .playlists)
        case .artists: MacLibraryGrid(kind: .artists)
        case .stats: StatsView()
        case .lastFM: MacLastFMView()
        case .userPlaylist(let id): UserPlaylistView(id: id).id(id)
        }
    }

    private func submit(_ text: String) {
        if let link = YouTubeLink(text: text) {
            search.query = ""
            model.openLink(link)
            return
        }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if model.settings.savesSearchHistory { library.recordSearch(text) }
        search.query = text
        section = .search
        Task { await search.search(text, music: model.music) }
    }
}

/// A row of the sidebar's foot: lit under the pointer.
private struct MacSidebarButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.06 : 0)))
            }
            .onHover { hovering = $0 }
    }
}

/// One sidebar row's look, drawn the Mac way.
struct MacSidebarLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var count = 0
    var dimmed = false
    @State private var hovering = false

    static let insets = EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(dimmed ? Color.secondary : Color.accentColor)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.primary.opacity(hovering ? 0.05 : 0)))
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}
