import KodaCore
import SwiftUI

/// Shuffle, repeat and autoplay over the list of what plays next.
struct QueuePanel: View {
    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 12) {
            modeToggles
            // Above the list rather than a sticky section header: iOS draws those on a band
            // of their own, which showed as an outline over the songs scrolling under it.
            HStack {
                Text(player.queue.upcoming.isEmpty ? "Nothing Up Next" : "Up Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if !player.queue.upcoming.isEmpty {
                    Button("Clear") { withAnimation { player.clearUpcoming() } }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 4)
            List {
                Section {
                    ForEach(player.queue.upcoming) { item in
                        QueueRow(song: item.song)
                            .contentShape(.rect)
                            .onTapGesture { player.jump(to: item.id) }
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
            .id(player.queue.isShuffled)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }

    private var modeToggles: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                toggle("Shuffle", systemImage: "shuffle", isOn: player.queue.isShuffled) {
                    player.setShuffle(!player.queue.isShuffled)
                }
                toggle(player.queue.repeatMode == .one ? "Repeat One" : "Repeat",
                       systemImage: player.queue.repeatMode == .one ? "repeat.1" : "repeat",
                       isOn: player.queue.repeatMode != .off) {
                    player.cycleRepeat()
                }
                toggle("Autoplay", systemImage: "infinity", isOn: player.autoplay) {
                    player.autoplay.toggle()
                }
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : .white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.white).interactive() : .regular.interactive(), in: .capsule)
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
