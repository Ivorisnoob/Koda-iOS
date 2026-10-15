import KodaCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @State private var homePath: [Route] = []
    @State private var libraryPath: [Route] = []
    @State private var searchPath: [Route] = []
    @Namespace private var playerTransition

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView().routeDestinations()
                }
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack(path: $libraryPath) {
                    LibraryView().routeDestinations()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView().routeDestinations()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // iOS 27 made the automatic edge effect hard: an opaque band under the bars. A soft one
        // blurs content progressively instead. It applies to every scroll view below here.
        .scrollEdgeEffectStyle(.soft, for: .all)
        .modifier(MiniPlayerAccessory(isEnabled: player.current != nil) {
            MiniPlayer()
                .matchedTransitionSource(id: "player", in: playerTransition)
        })
        .fullScreenCover(isPresented: $model.isNowPlayingPresented) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "player", in: playerTransition))
        }
        .playlistPicker(whenOnTop: !model.isNowPlayingPresented)
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
