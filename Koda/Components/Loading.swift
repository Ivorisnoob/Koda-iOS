import KodaCore
import SwiftUI

/// A page's data as it loads.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

extension Error {
    /// What a listener is told when something did not load.
    var friendlyMessage: String {
        switch self as? MusicError {
        case .network: "Check your connection and try again."
        case .botCheck: "YouTube is refusing requests right now. Try again in a little while."
        case .unplayable(let reason): reason ?? "This isn't available."
        case .badResponse: "YouTube sent something unexpected. Try again."
        case nil: "Something went wrong. Try again."
        }
    }
}

/// Loading, failed or loaded, with a retry that re-runs `load`.
struct AsyncContent<Value, Content: View>: View {
    let state: LoadState<Value>
    var retry: () async -> Void
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 300)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 300)
        case .loaded(let value):
            content(value)
        }
    }
}

/// Play and Shuffle side by side, tinted with the page's colour.
struct PlayShuffleButtons: View {
    var tint: Color = .accentColor
    var shuffleTitle = "Shuffle"
    let play: () -> Void
    let shuffle: () -> Void
    @State private var taps = 0

    var body: some View {
        HStack(spacing: 12) {
            Button {
                taps += 1
                play()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            Button {
                taps += 1
                shuffle()
            } label: {
                Label(shuffleTitle, systemImage: shuffleTitle == "Shuffle" ? "shuffle" : "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.body.weight(.semibold))
        .controlSize(.large)
        .buttonStyle(.glassProminent)
        .tint(tint)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
