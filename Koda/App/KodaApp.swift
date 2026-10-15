import KodaCore
import SwiftUI

@main
struct KodaApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
                // Pausing listening history pauses scrobbling with it.
                .onChange(of: model.settings.savesListeningHistory) { _, saves in model.lastFM.isPaused = !saves }
                .preferredColorScheme(model.settings.theme.colorScheme)
                .frame(minWidth: Platform.isMac ? 960 : nil, minHeight: Platform.isMac ? 600 : nil)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands { KodaCommands(model: model) }
        .onChange(of: scenePhase) { _, phase in
            // The queue and position survive the app being closed from the switcher.
            if phase != .active { model.saveState() }
            if phase == .active { model.lastFM.syncSoon() }
        }

        #if targetEnvironment(macCatalyst)
        // Keyed by one value, so asking again brings the open Settings window forward.
        WindowGroup("Settings", id: MacSettingsView.windowID, for: String.self) { _ in
            MacSettingsView()
                .appEnvironment(model)
                .preferredColorScheme(model.settings.theme.colorScheme)
        }
        .defaultSize(width: 820, height: 600)
        #endif
    }
}

extension View {
    /// The app's shared objects. Given again to anything presented full screen: the Mac shows a
    /// presented view in its own hosting controller, which doesn't inherit them.
    func appEnvironment(_ model: AppModel) -> some View {
        environment(model)
            .environment(model.player)
            .environment(model.library)
            .environment(model.downloads)
            .environment(model.lastFM)
    }
}
