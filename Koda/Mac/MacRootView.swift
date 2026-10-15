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
    /// Each section's own trail of pages, so going back to a section returns to where you were.
    @State private var paths: [MacSection: [Route]] = [:]
    @State private var home = HomeModel()
    @State private var search = SearchModel()
    @FocusState private var searchFocused: Bool
    @State private var showsNowPlaying = false
    @State private var namingPlaylist = false
    @State private var draftName = ""
    @State private var renaming: UserPlaylist?
    @State private var deleting: UserPlaylist?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        dialogs(nowPlayingLayer(routing(searching(splitView))))
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 320)
        } detail: {
            NavigationStack(path: path) {
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
    }

    private func searching<V: View>(_ content: V) -> some View {
        @Bindable var search = search
        return content
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
    }

    private func routing<V: View>(_ content: V) -> some View {
        content
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
            path.wrappedValue.append(route)
        }
        .onOpenURL { url in
            if !model.open(url) { model.linkError = "Koda can open YouTube Music songs, albums, playlists and artists." }
        }
    }

    private func nowPlayingLayer<V: View>(_ content: V) -> some View {
        content
        // Now Playing is a layer of the window rather than a full-screen presentation: presented,
        // Catalyst hides the window's toolbar under it and the sidebar button came back stuck.
        // While it is open the window's toolbar steps away, as Music's full-window player does,
        // leaving only the window buttons over the song's colours. It fades and settles in
        // rather than sliding up, which is the phone's gesture, not the Mac's.
        .overlay {
            if showsNowPlaying {
                NowPlayingView()
                    .environment(\.closeNowPlaying) { showsNowPlaying = false }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                            removal: .opacity.combined(with: .scale(scale: 0.985))))
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.32), value: showsNowPlaying)
        .background { WindowToolbarHider(isHidden: showsNowPlaying) }
        .onChange(of: model.isNowPlayingPresented) { _, shown in showsNowPlaying = shown }
        .onChange(of: showsNowPlaying) { _, shown in model.isNowPlayingPresented = shown }
        .task(id: player.current?.artwork) { await model.nowPlayingPalette.load(player.current?.artwork) }
        .playlistPicker(whenOnTop: !showsNowPlaying)
        // Settings is a window of its own on the Mac; one, brought forward if it's already open.
        .onChange(of: model.isProfilePresented) { _, asked in
            guard asked else { return }
            model.isProfilePresented = false
            openWindow(id: MacSettingsView.windowID, value: MacSettingsView.windowID)
        }
    }

    private func dialogs<V: View>(_ content: V) -> some View {
        content
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                MacSidebarGlance(openQueue: { model.showNowPlaying(.queue) }, openStats: { section = .stats })
                profileButton
            }
        }
    }

    /// A Mac sidebar row: 13-point text, the symbol in the accent colour, and when selected the
    /// soft rounded fill the Mac's own sidebars use, rather than Catalyst's iPad-sized row.
    private func sidebarRow(_ title: String, _ systemImage: String, _ target: MacSection, count: Int = 0) -> some View {
        Button {
            // Clicking the section you're in goes back to its first page, as Music's sidebar does.
            if section == target { paths[target] = [] } else { section = target }
        } label: {
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
                    Text("Settings").font(.caption).foregroundStyle(.secondary)
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
        case .home: MacHomeView(model: home)
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

    private var path: Binding<[Route]> {
        let current = section ?? .home
        return Binding(get: { paths[current] ?? [] }, set: { paths[current] = $0 })
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
        paths[.search] = []
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

    /// None of its own: the sidebar list already keeps rows off its edges, as the Mac's do.
    static let insets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(dimmed ? Color.secondary : Color.accentColor)
                .frame(width: 18)
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
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.primary.opacity(hovering ? 0.05 : 0)))
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}

/// What the foot of the sidebar keeps in view, as the Mac's sidebars do: the next songs in the
/// queue, each a click away, and today's listening.
private struct MacSidebarGlance: View {
    let openQueue: () -> Void
    let openStats: () -> Void
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !player.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Up Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Show All", action: openQueue)
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                    ForEach(player.upcoming.prefix(3)) { item in
                        MacUpNextRow(item: item)
                    }
                }
            }
            Button(action: openStats) {
                HStack(spacing: 10) {
                    Image(systemName: "headphones")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(library.listening(on: Date()).listeningText) today")
                            .font(.system(size: 12, weight: .semibold))
                        let streak = library.streak()
                        Text(streak == 0 ? "Play something to start a streak" : streak == 1 ? "1-day streak" : "\(streak)-day streak")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Listening Stats")
        }
        .padding(10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .animation(.smooth, value: player.upcoming.prefix(3).map(\.id))
    }
}

/// A song waiting in the queue: a click plays it now.
private struct MacUpNextRow: View {
    let item: QueueItem
    @Environment(Player.self) private var player
    @State private var hovering = false

    var body: some View {
        Button { player.jump(to: item.id) } label: {
            HStack(spacing: 8) {
                ArtworkView(artwork: item.song.artwork, size: 28, cornerRadius: 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.song.title).font(.system(size: 12, weight: .medium))
                    Text(item.song.artistLine).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if hovering {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .padding(4)
            .background(.primary.opacity(hovering ? 0.06 : 0), in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { SongMenuItems(song: item.song) }
        .help("Play Now")
    }
}

/// Hides the window's toolbar and title while `isHidden`, keeping the window buttons: what the
/// Mac does for a full-window view. Catalyst gives the window's titlebar to its scene.
private struct WindowToolbarHider: UIViewRepresentable {
    let isHidden: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        #if targetEnvironment(macCatalyst)
        let hidden = isHidden
        // The view may not be in its window yet on the first update.
        DispatchQueue.main.async {
            guard let titlebar = view.window?.windowScene?.titlebar else { return }
            titlebar.toolbar?.isVisible = !hidden
            titlebar.titleVisibility = hidden ? .hidden : .visible
        }
        #endif
    }
}
