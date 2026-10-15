import KodaCore
import SwiftUI

/// Shuffle, repeat and autoplay over the list of what plays next.
struct QueuePanel: View {
    @Environment(Player.self) private var player
    /// What Clear removed, offered back for a few seconds.
    @State private var cleared: [Song]?

    var body: some View {
        VStack(spacing: 12) {
            modeToggles
            // Above the list rather than a sticky section header: iOS draws those on a band
            // of their own, which showed as an outline over the songs scrolling under it.
            HStack {
                Text(player.upcoming.isEmpty ? "Nothing Up Next" : "Up Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let cleared {
                    Button("Undo") { undoClear(cleared) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                } else if !player.upcoming.isEmpty {
                    Button("Clear") { clear() }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.2), value: cleared == nil)
            List {
                Section {
                    ForEach(player.upcoming) { item in
                        QueueRow(song: item.song)
                            .contentShape(.rect)
                            .onTapGesture { player.jump(to: item.id) }
                            // The cover lines up with the toggles and the heading above.
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.15))
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) { player.remove(item.id) }
                            }
                    }
                    .onMove { source, destination in player.moveUpcoming(fromOffsets: source, toOffset: destination) }
                }
            }
            .listStyle(.plain)
            // Shuffle reorders every row; a fresh list draws only the rows on screen,
            // where diffing would animate a move for each of hundreds of songs.
            .id(player.isShuffled)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .task(id: cleared == nil) {
            guard cleared != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            cleared = nil
        }
    }

    private func clear() {
        cleared = player.upcoming.map(\.song)
        withAnimation { player.clearUpcoming() }
    }

    /// Autoplay may have filled the queue again since; what was cleared comes back in its place.
    private func undoClear(_ songs: [Song]) {
        cleared = nil
        withAnimation {
            player.clearUpcoming()
            player.addToQueue(songs)
        }
    }

    private var modeToggles: some View {
        HStack(spacing: 8) {
            toggle("Shuffle", systemImage: "shuffle", isOn: player.isShuffled) {
                player.setShuffle(!player.isShuffled)
            }
            toggle(player.repeatMode == .one ? "Repeat One" : "Repeat",
                   systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                   isOn: player.repeatMode != .off) {
                player.cycleRepeat()
            }
            toggle("Autoplay", systemImage: "infinity", isOn: player.autoplay) {
                player.autoplay.toggle()
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PlayerToggleStyle(isOn: isOn, offFill: 0.12))
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct QueueRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: song.artwork, size: 44, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(song.artistLine).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}
