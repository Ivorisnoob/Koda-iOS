import AVKit
import KodaCore
import MediaPlayer
import SwiftUI

/// The progress bar: drag anywhere on it to seek; it thickens under the finger.
///
/// Position is read from the player's time anchor inside a TimelineView, so
/// only this bar redraws as the song plays, never the screen around it.
struct Scrubber: View {
    @Environment(Player.self) private var player
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let duration = max(player.duration, 1)
            let fraction = dragFraction ?? min(1, player.position(at: context.date) / duration)
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white.opacity(dragFraction == nil ? 0.85 : 1))
                            .frame(width: max(0, width * fraction))
                    }
                    // Light runs along the bar while the song loads or the network catches up.
                    .sheen(player.isBuffering, period: 1.1)
                    .clipShape(.capsule)
                    .frame(height: dragFraction == nil ? 6 : 12)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(1, max(0, value.location.x / width))
                            }
                            .onEnded { value in
                                let target = min(1, max(0, value.location.x / width)) * duration
                                player.seek(to: target)
                                dragFraction = nil
                            })
                }
                .frame(height: 24)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: dragFraction == nil)

                HStack {
                    Text(format(fraction * duration))
                    Spacer()
                    Text("-" + format(max(0, duration - fraction * duration)))
                }
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue("\(format(fraction * duration)) of \(format(duration))")
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 10 : -10
                player.seek(to: player.position() + step)
            }
        }
        .sensoryFeedback(.selection, trigger: dragFraction == nil)
        .disabled(player.phase != .ready)
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        return Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// The system volume slider; the only way an app moves the phone's media volume.
struct VolumeSlider: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption)
            SystemVolumeView()
            Image(systemName: "speaker.wave.3.fill").font(.caption)
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

private struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(Color.accentColor)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
