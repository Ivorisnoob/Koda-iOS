import KodaCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @State private var homePath: [Route] = []
    @State private var libraryPath: [Route] = []
    @State private var searchPath: [Route] = []
    @Namespace private var playerTransition
    /// Now Playing's presentation, owned here rather than bound to the model: when the cover's
    /// binding comes from an @Observable model, the zoom out of the tab bar accessory finds no
    /// source view and falls back to a plain slide up (FB20772137, iOS 26.1 on). The model's
    /// `isNowPlayingPresented` mirrors it, for opening and closing from elsewhere.
    @State private var showsNowPlaying = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView().routeDestinations()
                }
                .modifier(playerBar)
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack(path: $libraryPath) {
                    LibraryView().routeDestinations()
                }
                .modifier(playerBar)
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView().routeDestinations()
                }
                .modifier(playerBar)
            }
        }
        .modifier(TabStyle())
        .tabBarMinimizeBehavior(.onScrollDown)
        // iOS 27 made the automatic edge effect hard: an opaque band under the bars. A soft one
        // blurs content progressively instead. It applies to every scroll view below here.
        .scrollEdgeEffectStyle(.soft, for: .all)
        .modifier(MiniPlayerAccessory(isEnabled: player.current != nil && !Platform.isMac) {
            MiniPlayer { showsNowPlaying = true }
                .matchedTransitionSource(id: "player", in: playerTransition)
        })
        .fullScreenCover(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "player", in: playerTransition))
        }
        .sheet(isPresented: $model.isProfilePresented) { ProfileView() }
        .onChange(of: model.isNowPlayingPresented) { _, shown in showsNowPlaying = shown }
        .onChange(of: showsNowPlaying) { _, shown in model.isNowPlayingPresented = shown }
        // Now Playing opens already in the song's colours, rather than fading into them mid-zoom.
        .task(id: player.current?.artwork) { await model.nowPlayingPalette.load(player.current?.artwork) }
        .playlistPicker(whenOnTop: !showsNowPlaying)
        .onOpenURL { url in
            if !model.open(url) { model.linkError = "Koda can open YouTube Music songs, albums, playlists and artists." }
        }
        .alert("Couldn't Open Link", isPresented: Binding(get: { model.linkError != nil }, set: { if !$0 { model.linkError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.linkError ?? "")
        }
        .onChange(of: model.pendingRoute) { _, route in
            guard let route else { return }
            model.pendingRoute = nil
            switch model.selectedTab {
            case .home: homePath.append(route)
            case .library: libraryPath.append(route)
            case .search: searchPath.append(route)
            }
        }
    }
}

extension RootView {
    /// The Mac's player bar, under each page rather than across the sidebar.
    private var playerBar: MacPlayerBarInset {
        MacPlayerBarInset(isEnabled: Platform.isMac && player.current != nil) { panel in
            model.requestedPanel = panel
            showsNowPlaying = true
        }
    }
}

private struct MacPlayerBarInset: ViewModifier {
    let isEnabled: Bool
    let open: (NowPlayingView.Panel) -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if isEnabled {
                MacPlayerBar(open: open)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.35), value: isEnabled)
    }
}

/// Tabs along the bottom on the iPhone; a sidebar on the Mac, where there is room for one.
private struct TabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if Platform.isMac {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

/// The mini player as the tab bar's accessory; hidden while nothing is queued where the system allows it.
private struct MiniPlayerAccessory<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    @ViewBuilder var accessory: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled, content: accessory)
        } else {
            content.tabViewBottomAccessory(content: accessory)
        }
    }
}
