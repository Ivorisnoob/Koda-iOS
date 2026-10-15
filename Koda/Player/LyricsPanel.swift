import KodaCore
import SwiftUI

/// Lyrics for the playing song: synced ones follow the song and a tap on a line seeks to it.
struct LyricsPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @State private var state: LoadState<Lyrics?> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task(id: player.current?.id) {
            guard let song = player.current else { return }
            state = .loading
            let found = await app.lyrics.lyrics(for: song)
            guard player.current?.id == song.id else { return }
            state = .loaded(found)
        }
    }
}

private struct SyncedLyrics: View {
    let lines: [LyricLine]
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var userScrolled = false

    /// The listener's correction for this song; positive shows each line later.
    private var offset: TimeInterval { player.current.map { library.lyricsOffset(for: $0.id) } ?? 0 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            // Lead the audio slightly so a line lights up as it is sung, not after.
            let current = Lyrics.index(of: player.position(at: context.date) + 0.25 - offset, in: lines)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(lines) { line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title2.bold())
                                .foregroundStyle(.white.opacity(line.id == current ? 1 : 0.35))
                                .scaleEffect(line.id == current ? 1 : 0.97, anchor: .leading)
                                .blur(radius: current.map { abs(line.id - $0) > 2 ? 0.6 : 0 } ?? 0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                                .contentShape(.rect)
                                .onTapGesture {
                                    player.seek(to: max(0, line.time + offset))
                                    userScrolled = false
                                }
                                .animation(.easeOut(duration: 0.3), value: current)
                        }
                    }
                    .padding(.vertical, 120)
                }
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { userScrolled = true }
                }
                .onChange(of: current) { _, index in
                    guard let index, !userScrolled else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.35)) }
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.35)) }
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottomTrailing) {
            if userScrolled {
                Button("Follow", systemImage: "arrow.down.to.line") { userScrolled = false }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.glass)
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let id = player.current?.id {
                LyricsTimingControl(songId: id)
                    .padding(8)
            }
        }
    }
}

/// Nudges synced lyrics earlier or later for one song, when they run ahead of or behind the singing.
private struct LyricsTimingControl: View {
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
