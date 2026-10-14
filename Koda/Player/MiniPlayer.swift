import KodaCore
import SwiftUI

/// The bar above the tabs: what is playing, play/pause and skip. A tap opens Now Playing.
///
/// When the tab bar shrinks on scroll the system moves the accessory inline
/// beside it, where there is room for less, so the subtitle and skip go.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: player.current?.artwork, size: isInline ? 28 : 36, cornerRadius: isInline ? 6 : 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.current?.title ?? "Not Playing")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !isInline, let artist = player.current?.artistLine {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)

            PlayPauseButton(size: 20)
            if !isInline {
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(player.current == nil)
                .accessibilityLabel("Next")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .contentShape(.rect)
        .onTapGesture {
            guard player.current != nil else { return }
            model.isNowPlayingPresented = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open Now Playing") { model.isNowPlayingPresented = true }
    }
}

/// Play/pause with a spinner while the song is loading.
struct PlayPauseButton: View {
    var size: CGFloat
    @Environment(Player.self) private var player
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            player.togglePlayPause()
        } label: {
            ZStack {
                if player.isBuffering && player.phase == .loading {
                    ProgressView().controlSize(size > 30 ? .large : .regular)
                } else {
                    Image(systemName: player.wantsToPlay ? "pause.fill" : "play.fill")
                        .font(.system(size: size))
                        .contentTransition(.symbolEffect(.replace.downUp))
                }
            }
            .frame(width: size * 1.8, height: size * 1.8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(player.current == nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(player.wantsToPlay ? "Pause" : "Play")
    }
}
