import KodaCore
import SwiftUI

/// Lyrics for the playing song: synced ones follow the song (word by word when the
/// provider has word timing) and a tap on a line seeks to it.
struct LyricsPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @State private var state: LoadState<Lyrics?> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                LyricsLoading()
            case .failed, .loaded(nil):
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble", description: Text("Lyrics for this song aren't available."))
                    .foregroundStyle(.white)
            case .loaded(.plain(let text)?):
                ScrollView {
                    Text(text)
                        .font(.title3.weight(.semibold))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            case .loaded(.synced(let lines)?):
                SyncedLyrics(lines: lines)
            }
        }
        .frame(maxHeight: .infinity)
        .task(id: LyricsRequest(songId: player.current?.id, sources: app.settings.lyricsSources)) {
            guard let song = player.current else { return }
            state = .loading
            let found = await app.lyrics.lyrics(for: song, sources: app.settings.lyricsSources)
            guard player.current?.id == song.id else { return }
            state = .loaded(found)
        }
    }
}

/// Nudges synced lyrics earlier or later for one song, when they run ahead of or behind the singing.
struct LyricsTimingControl: View {
    let songId: String
    @Environment(Library.self) private var library
    @State private var isOpen = false

    private static let step: TimeInterval = 0.2

    var body: some View {
        let offset = library.lyricsOffset(for: songId)
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                if isOpen {
                    nudge("Earlier", systemImage: "minus", by: -Self.step, from: offset)
                    Button {
                        library.setLyricsOffset(0, for: songId)
                    } label: {
                        Text(offset == 0 ? "In sync" : String(format: "%+.1fs", offset))
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .frame(minWidth: 64, minHeight: 36)
                            .contentTransition(.numericText(value: offset))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Lyrics timing \(offset == 0 ? "unchanged" : String(format: "%+.1f seconds", offset))")
                    .accessibilityHint("Resets the timing")
                    nudge("Later", systemImage: "plus", by: Self.step, from: offset)
                }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isOpen.toggle() }
                } label: {
                    Image(systemName: isOpen ? "xmark" : "timer")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glassEffect(offset != 0 && !isOpen ? .regular.tint(.white.opacity(0.3)).interactive() : .regular.interactive(), in: .circle)
                .accessibilityLabel(isOpen ? "Close timing" : "Adjust lyrics timing")
            }
        }
        .animation(.snappy(duration: 0.2), value: offset)
    }

    private func nudge(_ label: String, systemImage: String, by step: TimeInterval, from offset: TimeInterval) -> some View {
        Button {
            library.setLyricsOffset(offset + step, for: songId)
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .buttonRepeatBehavior(.enabled)
        .sensoryFeedback(.selection, trigger: offset)
        .accessibilityLabel("Show lyrics \(label.lowercased())")
        .transition(.scale.combined(with: .opacity))
    }
}

/// What the panel looks lyrics up for; a change of song or of sources looks again.
private struct LyricsRequest: Equatable {
    var songId: String?
    var sources: [LyricsSource]
}
