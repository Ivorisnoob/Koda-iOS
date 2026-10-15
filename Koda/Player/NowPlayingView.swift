import KodaCore
import SwiftUI

/// The full-screen player.
struct NowPlayingView: View {
    enum Panel: Equatable {
        case artwork, lyrics, queue
    }

    @Environment(AppModel.self) private var app
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var palette = PaletteModel()
    @State private var panel: Panel = .artwork
    @Namespace private var artworkSpace

    var body: some View {
        ZStack {
            MeshBackground(palette: palette.palette, isAnimating: player.wantsToPlay && app.settings.animatesPlayerBackground)
            VStack(spacing: 0) {
                topBar
                switch panel {
                case .artwork:
                    Spacer(minLength: 12)
                    bigArtwork
                    Spacer(minLength: 12)
                    titleRow
                case .lyrics:
                    compactHeader
                    LyricsPanel()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .queue:
                    compactHeader
                    QueuePanel()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if case .failed(let message) = player.phase {
                    FailureBanner(message: message) { player.resume() }
                        .padding(.top, 12)
                }
                Scrubber()
                    .padding(.top, 20)
                TransportControls()
                    .padding(.vertical, 18)
                VolumeSlider()
                    .frame(height: 34)
                bottomBar
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .overlay {
                if player.current != nil { floatingArtwork }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .task(id: player.current?.artwork) { await palette.load(player.current?.artwork) }
        .onChange(of: player.current == nil) { _, isEmpty in if isEmpty { dismiss() } }
        .playlistPicker(whenOnTop: true)
    }

    /// The song was asked for and no sound has come yet.
    private var isLoadingSong: Bool { player.isBuffering && player.phase == .loading }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")
            Spacer()
            if app.sleepTimer.isActive {
                SleepTimerPill()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Capsule().fill(.white.opacity(0.4)).frame(width: 36, height: 5)
            }
            Spacer()
            if let song = player.current {
                Menu {
                    SongMenuItems(song: song)
                    Section { SleepTimerMenu() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("More")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: app.sleepTimer.isActive)
    }

    /// Where the big cover goes. The cover itself is `floatingArtwork`, drawn once over
    /// the whole screen, so it moves and resizes between here and the compact header
    /// rather than fading out of one and into the other.
    private var bigArtwork: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Color.clear
                .frame(width: side, height: side)
                .matchedGeometryEffect(id: "artwork", in: artworkSpace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var floatingArtwork: some View {
        let big = panel == .artwork
        let radius: CGFloat = big ? 18 : 8
        return ArtworkView(artwork: player.current?.artwork, size: 380, cornerRadius: radius, fillsFrame: true)
            // While the song loads, light passes over the cover and it waits a little small,
            // then settles to full size the moment sound starts.
            .sheen(big && isLoadingSong)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(big ? (isLoadingSong ? 0.2 : 0.35) : 0.25), radius: big ? 30 : 8, y: big ? 18 : 4)
            // The cover breathes back when paused, like a record lifted off.
            .scaleEffect(big ? (player.wantsToPlay ? (isLoadingSong ? 0.93 : 1) : 0.84) : 1)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.wantsToPlay)
            .animation(.spring(response: 0.45, dampingFraction: 0.62), value: isLoadingSong)
            .matchedGeometryEffect(id: "artwork", in: artworkSpace, isSource: false)
            .onTapGesture { if !big { setPanel(.artwork) } }
            .accessibilityHidden(true)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.title3.bold())
                    .lineLimit(1)
                artistButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let song = player.current {
                LikeButton(song: song)
            }
        }
    }

    private var artistButton: some View {
        Button {
            guard let artist = player.current?.artists.first(where: { $0.id != nil }), let id = artist.id else { return }
            app.open(.artist(ArtistSummary(id: id, name: artist.name)))
        } label: {
            Text(player.current?.artistLine ?? "")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    /// The cover, title and like button in one row, above lyrics or the queue.
    private var compactHeader: some View {
        HStack(spacing: 14) {
            Color.clear
                .frame(width: 64, height: 64)
                .matchedGeometryEffect(id: "artwork", in: artworkSpace)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "").font(.headline).lineLimit(1)
                artistButton.font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let song = player.current {
                LikeButton(song: song)
            }
        }
        .padding(.vertical, 16)
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 0) {
                panelButton(.lyrics, systemImage: "quote.bubble", activeImage: "quote.bubble.fill", label: "Lyrics")
                Spacer()
                AirPlayButton()
                    .frame(width: 52, height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                Spacer()
                panelButton(.queue, systemImage: "list.bullet", activeImage: "list.bullet", label: "Queue")
            }
        }
    }

    /// `activeImage` is spelled out because not every symbol has a filled form; `list.bullet.fill` draws nothing.
    private func panelButton(_ target: Panel, systemImage: String, activeImage: String, label: String) -> some View {
        let active = panel == target
        return Button {
            setPanel(active ? .artwork : target)
        } label: {
            Image(systemName: active ? activeImage : systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 52, height: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(active ? .regular.tint(.white.opacity(0.35)).interactive() : .regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: active)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func setPanel(_ next: Panel) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { panel = next }
    }
}

/// The cover's colours as a slowly moving mesh. It holds still while paused so it costs nothing then.
struct MeshBackground: View {
    let palette: Palette
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !isAnimating || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(t), colors: palette.mesh)
        }
        .overlay(Color.black.opacity(0.18))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: palette)
    }

    private func points(_ t: TimeInterval) -> [SIMD2<Float>] {
        // Only the inner points drift; the corners and edges stay put so the mesh always fills the screen.
        let a = Float(sin(t * 0.35)) * 0.12, b = Float(cos(t * 0.27)) * 0.12
        return [
            [0, 0], [0.5 + a * 0.5, 0], [1, 0],
            [0, 0.5 + b * 0.5], [0.5 + a, 0.5 + b], [1, 0.5 - a * 0.5],
            [0, 1], [0.5 - b * 0.5, 1], [1, 1],
        ]
    }
}

struct LikeButton: View {
    let song: Song
    @Environment(Library.self) private var library

    var body: some View {
        let liked = library.isLiked(song)
        Button {
            library.toggleLike(song)
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.title3.weight(.semibold))
                .foregroundStyle(liked ? Color.pink : .white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: liked)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Unlike" : "Like")
    }
}

struct TransportControls: View {
    @Environment(Player.self) private var player
    @State private var skips = 0

    var body: some View {
        HStack {
            Spacer()
            Button {
                skips += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill").font(.system(size: 32))
                    .frame(width: 72, height: 60)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Previous")
            Spacer()
            PlayPauseButton(size: 44)
            Spacer()
            Button {
                skips += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill").font(.system(size: 32))
                    .frame(width: 72, height: 60)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Next")
            Spacer()
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce.down, value: skips)
        .sensoryFeedback(.impact(weight: .light), trigger: skips)
        .disabled(player.current == nil)
    }
}

private struct FailureBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry).font(.footnote.weight(.semibold)).buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Time left on the sleep timer, at the top of Now Playing; a tap changes or ends it.
private struct SleepTimerPill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            SleepTimerMenu()
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(app.sleepTimer.label(at: context.date), systemImage: "moon.fill")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .frame(height: 30)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sleep timer")
    }
}
