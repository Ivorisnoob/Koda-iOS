import KodaCore
import SwiftUI

struct SettingsView: View {
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        @Bindable var player = player
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $player.autoplay) {
                        Label("Autoplay", systemImage: "infinity")
                    }
                } footer: {
                    Text("When the queue ends, keep playing songs like the last one.")
                }
                Section {
                    Button("Clear Listening History", role: .destructive) { confirmClear = true }
                        .disabled(library.recent.isEmpty)
                    Button("Clear Search History", role: .destructive) { library.clearSearches() }
                        .disabled(library.searches.isEmpty)
                } footer: {
                    Text("Your library and history stay on this iPhone.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Link(destination: URL(string: "https://github.com/Ivorisnoob/Koda-iOS")!) {
                        Label("Koda on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Koda is an unofficial client and is not affiliated with YouTube or Google.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Clear your listening history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { library.clearHistory() }
            } message: {
                Text("Recently played and Quick picks start over.")
            }
        }
    }
}
