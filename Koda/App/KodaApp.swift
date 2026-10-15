import KodaCore
import SwiftUI

@main
struct KodaApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.player)
                .environment(model.library)
                .environment(model.downloads)
                .preferredColorScheme(model.settings.theme.colorScheme)
                .frame(minWidth: Platform.isMac ? 820 : nil, minHeight: Platform.isMac ? 600 : nil)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands { KodaCommands(model: model) }
        .onChange(of: scenePhase) { _, phase in
            // The queue and position survive the app being closed from the switcher.
            if phase != .active { model.saveState() }
        }
    }
}
