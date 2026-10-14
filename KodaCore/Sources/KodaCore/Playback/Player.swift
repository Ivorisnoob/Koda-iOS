import AVFoundation
import Foundation
import MediaPlayer
import Observation
import os

private let traceEnabled = ProcessInfo.processInfo.environment["KODA_TRACE"] == "1"
private let log = Logger(subsystem: "Koda", category: "Player")

/// Engine events, printed only under `KODA_TRACE=1`.
func trace(_ message: @autoclosure () -> String) {
    guard traceEnabled else { return }
    let line = message()
    print("TRACE", String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)), line)
    log.debug("\(line, privacy: .public)")
}

/// The music player: the queue, the AVFoundation pipeline under it, and the
/// system's Now Playing surfaces.
///
/// `AVQueuePlayer` holds at most two items, the current song and the one the
/// queue says comes next, so a song that ends runs straight into the next
/// without a gap. Every load is tagged with the queue occurrence it is for and
/// a generation; anything that comes back after the queue has moved on is
/// dropped rather than applied to whatever is current by then.
@MainActor
@Observable
public final class Player {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var queue = PlayQueue()
    public private(set) var phase: Phase = .idle
    /// Whether the listener wants sound: true while loading or buffering a song they pressed play on.
    public private(set) var wantsToPlay = false
    /// True while the player waits on the network with the intent to play.
    public private(set) var isBuffering = false
    public private(set) var duration: TimeInterval = 0
    /// Keep playing related songs when the queue runs out.
    public var autoplay = true {
        didSet { persistSettings() }
    }

    /// The last known position and when it was sampled; `position(at:)` runs it forward.
    public private(set) var timeAnchor = TimeAnchor(position: 0, date: .distantPast, rate: 0)

    public struct TimeAnchor: Equatable, Sendable {
        public var position: TimeInterval
        public var date: Date
        public var rate: Double
    }

    /// Called when a song starts playing, for history.
    public var onSongStarted: ((Song) -> Void)?
    /// Loads artwork for the lock screen; set by the app, which owns image decoding.
    public var artworkLoader: (@MainActor (URL) async -> MPMediaItemArtwork?)?

    public let music: YouTubeMusic
    private let avPlayer = AVQueuePlayer()
    private let storage: URL?

    /// The occurrence each loaded AVPlayerItem plays.
    private var occurrences: [ObjectIdentifier: UUID] = [:]
    /// Items put behind the current one; becoming current means a song changed at its start.
    private var preloaded: Set<ObjectIdentifier> = []
    /// The item AVFoundation played last, to tell a song that finished from one it dropped.
    private var lastAVItem: AVPlayerItem?
    private var itemStatusObservation: NSKeyValueObservation?
    private var stallWatchdog: Task<Void, Never>?
    /// How long the player may wait on the network, wanting to play, before the song is reloaded.
    var stallTimeout: Duration = .seconds(15)
    /// Test seam: rewrite a stream before it is played.
    var streamRewriter: ((ResolvedStream) -> ResolvedStream)?
    private var generation = 0
    private var nextGeneration = 0
    /// Occurrences already retried after a mid-play failure, so a broken song is skipped rather than looped.
    private var retried: Set<UUID> = []
    private var extendingWithRadio = false
    private var startedReported: UUID?
    private var observations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var nowPlayingArtworkFor: URL?

    public init(music: YouTubeMusic, storageDirectory: URL? = nil) {
        self.music = music
        storage = storageDirectory
        avPlayer.actionAtItemEnd = .advance
        observePlayer()
        configureRemoteCommands()
        restore()
    }

    // MARK: - Reading

    public var current: Song? { queue.current?.song }

    public var isMuted: Bool {
        get { avPlayer.isMuted }
        set { avPlayer.isMuted = newValue }
    }

    /// How many songs AVFoundation holds right now: 2 when the next one is preloaded.
    var loadedItemCount: Int { avPlayer.items().count }

    /// The playhead at `date`, run forward from the last sample at the playing rate.
    public func position(at date: Date = Date()) -> TimeInterval {
        let elapsed = timeAnchor.rate > 0 ? date.timeIntervalSince(timeAnchor.date) * timeAnchor.rate : 0
        let value = timeAnchor.position + max(0, elapsed)
        return duration > 0 ? min(value, duration) : value
    }

    // MARK: - Starting playback

    /// Replace the queue and play from `index`.
    public func play(_ songs: [Song], startAt index: Int = 0, shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        queue.replace(with: songs, startAt: index, shuffled: shuffled)
        retried = []
        wantsToPlay = true
        loadCurrent(at: 0)
    }

    /// Play `song` and follow it with its radio.
    public func startRadio(from song: Song) {
        play([song])
        let seed = queue.current?.id
        Task {
            guard let radio = try? await music.radio(for: song.id) else { return }
            guard queue.current?.id == seed else { return }
            queue.append(radio.songs.filter { $0.id != song.id })
            persistQueue()
            prepareNext()
        }
    }

    // MARK: - Transport

    public func togglePlayPause() {
        wantsToPlay ? pause() : resume()
    }

    public func resume() {
        guard queue.current != nil else { return }
        wantsToPlay = true
        activateAudioSession()
        if avPlayer.currentItem == nil || phase != .ready {
            loadCurrent(at: timeAnchor.position)
        } else {
            avPlayer.play()
        }
        updateNowPlaying()
    }

    public func pause() {
        wantsToPlay = false
        avPlayer.pause()
        sampleTime()
        updateNowPlaying()
        persistQueue()
    }

    public func next() {
        guard queue.current != nil else { return }
        if queue.peekNext(automatic: false) == nil {
            extendWithRadio(thenAdvance: true)
            return
        }
        move(to: queue.advance(automatic: false))
    }

    /// Back to the start of the song, or to the song before when already near the start.
    public func previous() {
        if position() > 3 || queue.history.isEmpty && queue.repeatMode == .off {
            seek(to: 0)
            return
        }
        let before = queue.current?.id
        queue.retreat()
        if queue.current?.id == before {
            seek(to: 0)
        } else {
            loadCurrent(at: 0)
        }
    }

    public func jump(to id: UUID) {
        guard id != queue.current?.id, queue.jump(to: id) else { return }
        wantsToPlay = true
        loadCurrent(at: 0)
    }

    public func seek(to seconds: TimeInterval) {
        let target = max(0, duration > 0 ? min(seconds, duration - 0.5) : seconds)
        timeAnchor = TimeAnchor(position: target, date: Date(), rate: timeAnchor.rate)
        avPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.sampleTime()
                self?.updateNowPlaying()
            }
        }
    }

    // MARK: - Queue editing

    public func setShuffle(_ on: Bool) {
        queue.setShuffle(on)
        queueChanged()
    }

    public func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        queueChanged()
    }

    public func setRepeat(_ mode: RepeatMode) {
        queue.repeatMode = mode
        queueChanged()
    }

    public func playNext(_ songs: [Song]) {
        let wasEmpty = queue.isEmpty
        queue.playNext(songs)
        if wasEmpty {
            wantsToPlay = true
            loadCurrent(at: 0)
        } else {
            queueChanged()
        }
    }

    public func addToQueue(_ songs: [Song]) {
        let wasEmpty = queue.isEmpty
        queue.append(songs)
        if wasEmpty {
            wantsToPlay = true
            loadCurrent(at: 0)
        } else {
            queueChanged()
        }
    }

    public func remove(_ id: UUID) {
        if queue.remove(id) { queueChanged() }
    }

    public func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpcoming(fromOffsets: source, toOffset: destination)
        queueChanged()
    }

    public func clearUpcoming() {
        queue.clearUpcoming()
        queueChanged()
    }

    /// Stop and empty the queue.
    public func stop() {
        generation += 1
        avPlayer.removeAllItems()
        occurrences = [:]
        preloaded = []
        lastAVItem = nil
        queue.clear()
        wantsToPlay = false
        isBuffering = false
        phase = .idle
        duration = 0
        timeAnchor = TimeAnchor(position: 0, date: Date(), rate: 0)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        persistQueue()
    }

    private func queueChanged() {
        persistQueue()
        prepareNext()
        updateRemoteCommandState()
    }

    // MARK: - Loading

    /// Make the queue's current song the one AVFoundation plays, from `position`.
    private func loadCurrent(at position: TimeInterval) {
        generation += 1
        let token = generation
        avPlayer.removeAllItems()
        occurrences = [:]
        preloaded = []
        lastAVItem = nil
        guard let item = queue.current else {
            phase = .idle
            return
        }
        // A song shown as playing from the old position would jump; show the new one at once.
        phase = .loading
        isBuffering = wantsToPlay
        duration = item.song.duration ?? 0
        timeAnchor = TimeAnchor(position: position, date: Date(), rate: 0)
        updateNowPlaying()
        persistQueue()
        if wantsToPlay { activateAudioSession() }

        Task {
            do {
                let stream = try await music.stream(for: item.song.id)
                guard token == generation, queue.current?.id == item.id else { return }
                let playerItem = makeItem(stream)
                occurrences[ObjectIdentifier(playerItem)] = item.id
                avPlayer.insert(playerItem, after: nil)
                if position > 1 {
                    await avPlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard token == generation else { return }
                }
                if let total = stream.duration, total > 0 { duration = total }
                applyLoudness(stream)
                phase = .ready
                if wantsToPlay { avPlayer.play() }
                sampleTime()
                updateNowPlaying()
                prepareNext()
            } catch is CancellationError {
            } catch {
                guard token == generation, queue.current?.id == item.id else { return }
                handleLoadFailure(error, for: item)
            }
        }
    }

    private func handleLoadFailure(_ error: Error, for item: QueueItem) {
        switch error as? MusicError {
        case .unplayable:
            // A verdict on this video; the rest of the queue is fine.
            skipBroken(item, message: "This song isn't available")
        case .botCheck:
            phase = .failed("YouTube is refusing playback right now. Try again in a little while.")
            isBuffering = false
            wantsToPlay = false
        default:
            phase = .failed("Couldn't load this song. Check your connection and try again.")
            isBuffering = false
            wantsToPlay = false
        }
        updateNowPlaying()
    }

    private func skipBroken(_ item: QueueItem, message: String) {
        guard queue.current?.id == item.id else { return }
        if let next = queue.peekNext(automatic: false), next.id != item.id {
            queue.advance(automatic: false)
            loadCurrent(at: 0)
        } else {
            phase = .failed(message)
            isBuffering = false
            wantsToPlay = false
        }
    }

    /// Keep the item after the current one in AVFoundation's queue matching what the queue says plays next.
    private func prepareNext() {
        guard phase == .ready, let currentItem = avPlayer.currentItem,
              let currentId = occurrences[ObjectIdentifier(currentItem)], currentId == queue.current?.id else { return }
        let wanted = queue.peekNext(automatic: true)
        let queued = avPlayer.items().dropFirst()
        if let wanted, queued.count == 1, let loaded = queued.first, occurrences[ObjectIdentifier(loaded)] == wanted.id {
            return
        }
        for stale in queued {
            occurrences[ObjectIdentifier(stale)] = nil
            preloaded.remove(ObjectIdentifier(stale))
            avPlayer.remove(stale)
        }
        nextGeneration += 1
        let token = nextGeneration
        guard let wanted else {
            if autoplay, queue.upcoming.isEmpty, queue.repeatMode == .off { extendWithRadio(thenAdvance: false) }
            return
        }
        Task {
            guard let stream = try? await music.stream(for: wanted.song.id) else { return }
            guard token == nextGeneration, queue.current?.id == currentId,
                  queue.peekNext(automatic: true)?.id == wanted.id,
                  let playing = avPlayer.currentItem, occurrences[ObjectIdentifier(playing)] == currentId,
                  avPlayer.items().count == 1 else { return }
            let item = makeItem(stream)
            occurrences[ObjectIdentifier(item)] = wanted.id
            preloaded.insert(ObjectIdentifier(item))
            trace("preloaded \(wanted.song.title)")
            avPlayer.insert(item, after: playing)
        }
    }

    private func makeItem(_ original: ResolvedStream) -> AVPlayerItem {
        let stream = streamRewriter?(original) ?? original
        let asset = AVURLAsset(url: stream.url, options: [AVURLAssetHTTPUserAgentKey: stream.userAgent])
        let item = AVPlayerItem(asset: asset)
        // AVFoundation reads YouTube's fragmented M4A as twice its real length
        // and plays silence for the second half instead of ending. [verified
        // October 2026: 403.1 s reported for a 201.6 s track] YouTube's own
        // duration is exact, so the item is told where it ends.
        if let duration = stream.duration, duration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: duration, preferredTimescale: 1000)
        }
        item.preferredForwardBufferDuration = 30
        item.audioTimePitchAlgorithm = .timeDomain
        return item
    }

    /// Bring loud masters down to YouTube's -14 LUFS target; quiet ones are left alone rather than boosted.
    private func applyLoudness(_ stream: ResolvedStream) {
        guard let db = stream.loudnessDb, db > 0 else {
            avPlayer.volume = 1
            return
        }
        avPlayer.volume = Float(max(0.4, pow(10, -db / 20)))
    }

    /// Move to `item` after a skip: instantly when it is the preloaded one, otherwise by loading it.
    private func move(to item: QueueItem?) {
        guard let item else { return }
        wantsToPlay = true
        let queued = avPlayer.items()
        if phase == .ready, queued.count == 2, occurrences[ObjectIdentifier(queued[1])] == item.id {
            occurrences[ObjectIdentifier(queued[0])] = nil
            avPlayer.advanceToNextItem()
            avPlayer.play()
            // currentItem's observer takes it from here.
        } else {
            loadCurrent(at: 0)
        }
    }

    /// The queue ran out: append the radio of the last song and carry on.
    private func extendWithRadio(thenAdvance: Bool) {
        guard autoplay, !extendingWithRadio, let last = queue.items.last else {
            if thenAdvance, queue.repeatMode == .off { seek(to: 0); pause() }
            return
        }
        extendingWithRadio = true
        let anchor = queue.current?.id
        Task {
            defer { extendingWithRadio = false }
            guard let radio = try? await music.radio(for: last.song.id) else {
                if thenAdvance { pause() }
                return
            }
            guard queue.current?.id == anchor else { return }
            let known = Set(queue.items.suffix(100).map(\.song.id))
            let fresh = radio.songs.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }
            queue.append(fresh)
            persistQueue()
            if thenAdvance {
                move(to: queue.advance(automatic: false))
            } else {
                prepareNext()
            }
        }
    }

    // MARK: - Observing AVFoundation

    private func observePlayer() {
        observations.append(avPlayer.observe(\.currentItem, options: [.new]) { @Sendable [weak self] player, _ in
            let item = player.currentItem.map(ObjectIdentifier.init)
            Task { @MainActor in self?.currentItemChanged(item) }
        })
        observations.append(avPlayer.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.timeControlChanged(status) }
        })
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleTime() }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let failed = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            trace("FAILED item error=\(err?.domain ?? "-") \(err?.code ?? 0) \(err?.localizedDescription ?? "") underlying=\((err?.userInfo[NSUnderlyingErrorKey] as? NSError)?.description ?? "-")")
            if let log = (note.object as? AVPlayerItem)?.errorLog()?.events.last { trace("errorLog \(log.errorStatusCode) \(log.errorDomain) \(log.errorComment ?? "")") }
            MainActor.assumeIsolated { self?.itemFailed(failed) }
        }
        center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let ended = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemEnded(ended) }
        }
        observeAudioSession()
    }

    /// AVQueuePlayer moved on by itself: the preloaded song is now playing.
    private func currentItemChanged(_ item: ObjectIdentifier?) {
        guard let item, let id = occurrences[item] else { return }
        // Its first time reading can still be the previous item's, so a preloaded song starts its clock at zero.
        let startsFresh = preloaded.remove(item) != nil
        trace("currentItemChanged fresh=\(startsFresh) queueMatches=\(queue.current?.id == id) t=\(avPlayer.currentTime().seconds)")
        let previous = lastAVItem
        lastAVItem = avPlayer.currentItem
        watchStatus(of: avPlayer.currentItem, id: id)
        // AVQueuePlayer drops a song that fails and moves on to the preloaded one.
        // That is not the song finishing, so the queue must not follow it.
        if let previous, ObjectIdentifier(previous) != item,
           let droppedId = occurrences[ObjectIdentifier(previous)], droppedId == queue.current?.id,
           stoppedEarly(previous) {
            let at = previous.currentTime().seconds
            trace("dropped early at \(at)")
            recover(droppedId, at: at.isFinite ? at : position())
            return
        }
        if queue.current?.id != id {
            if queue.peekNext(automatic: true)?.id == id {
                queue.advance(automatic: true)
            } else if !queue.jump(to: id) {
                return
            }
            retried.remove(id)
            if let song = queue.current?.song { duration = song.duration ?? duration }
            Task {
                if let stream = try? await music.stream(for: queue.current?.song.id ?? "") {
                    if let total = stream.duration { duration = total }
                    applyLoudness(stream)
                    updateNowPlaying()
                }
            }
            persistQueue()
        }
        if startsFresh {
            timeAnchor = TimeAnchor(position: 0, date: Date(), rate: Double(avPlayer.rate))
        } else {
            // Our own load of the current song; it may be seeking to a resume position.
            sampleTime()
        }
        updateNowPlaying()
        prepareNext()
    }

    /// A song ended with nothing preloaded behind it, so AVQueuePlayer stopped.
    /// When something was preloaded, AVQueuePlayer moves on by itself and
    /// `currentItemChanged` advances the queue; doing it here too would skip a song.
    private func itemEnded(_ item: ObjectIdentifier?) {
        trace("itemEnded known=\(item.flatMap { occurrences[$0] } != nil) items=\(avPlayer.items().count)")
        guard let item, let id = occurrences[item], id == queue.current?.id else { return }
        if avPlayer.items().contains(where: { ObjectIdentifier($0) != item && occurrences[ObjectIdentifier($0)] != nil }) { return }
        occurrences[item] = nil
        if queue.advance(automatic: true) != nil {
            loadCurrent(at: 0)
        } else {
            extendWithRadio(thenAdvance: true)
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        trace("timeControl \(status.rawValue) t=\(avPlayer.currentTime().seconds)")
        isBuffering = wantsToPlay && (status == .waitingToPlayAtSpecifiedRate || phase == .loading)
        armStallWatchdog(status)
        if status == .playing, let item = queue.current, startedReported != item.id {
            startedReported = item.id
            onSongStarted?(item.song)
        }
        sampleTime()
        updateNowPlaying()
    }

    /// A failure of the song AVFoundation is still on. When it has already moved
    /// past it to the preloaded song, `currentItemChanged` sees that instead.
    private func itemFailed(_ item: ObjectIdentifier?) {
        trace("itemFailed known=\(item.flatMap { occurrences[$0] } != nil) isCurrent=\(item.flatMap { occurrences[$0] } == queue.current?.id)")
        guard let item, let id = occurrences[item], id == queue.current?.id,
              avPlayer.currentItem.map(ObjectIdentifier.init) == item else { return }
        recover(id, at: position())
    }

    /// A broken URL does not always post a failure; the item's status turns failed and the player waits forever.
    private func watchStatus(of item: AVPlayerItem?, id: UUID) {
        itemStatusObservation = item?.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.queue.current?.id == id, self.occurrences.values.contains(id) else { return }
                trace("current item status failed")
                self.recover(id, at: self.position())
            }
        }
    }

    /// Waiting on the network for too long while the listener wants sound: reload the song where it was.
    private func armStallWatchdog(_ status: AVPlayer.TimeControlStatus) {
        stallWatchdog?.cancel()
        guard status == .waitingToPlayAtSpecifiedRate, wantsToPlay, phase == .ready, let id = queue.current?.id else { return }
        // A song that never got going is broken sooner than one that stalled mid-way on a slow network.
        let timeout = avPlayer.currentItem?.status == .readyToPlay ? stallTimeout : stallTimeout * 0.5
        stallWatchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.wantsToPlay, self.queue.current?.id == id,
                  self.avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            trace("stalled, reloading")
            self.recover(id, at: self.position())
        }
    }

    /// Whether `item` stopped short of its end rather than finishing.
    private func stoppedEarly(_ item: AVPlayerItem) -> Bool {
        if item.status == .failed { return true }
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime.seconds : item.duration.seconds
        let reached = item.currentTime().seconds
        guard end.isFinite, reached.isFinite, end > 0 else { return false }
        return reached < end - 2
    }

    /// A stream refused mid-play is usually a refused identity: retry once from
    /// the same spot with a fresh one, and skip the song if it fails again.
    private func recover(_ id: UUID, at seconds: TimeInterval) {
        guard let current = queue.current, current.id == id else { return }
        // Silence whatever AVQueuePlayer moved on to while this one reloads.
        avPlayer.pause()
        guard retried.insert(id).inserted else {
            skipBroken(current, message: "This song stopped loading")
            return
        }
        generation += 1
        let token = generation
        Task {
            await music.streamFailed(current.song.id)
            guard token == generation, queue.current?.id == id else { return }
            loadCurrent(at: seconds)
        }
    }

    private func sampleTime() {
        let seconds = avPlayer.currentTime().seconds
        trace("sample t=\(seconds) phase=\(phase) status=\(avPlayer.timeControlStatus.rawValue)")
        guard seconds.isFinite, phase == .ready else {
            timeAnchor.rate = 0
            return
        }
        let rate = avPlayer.timeControlStatus == .playing ? Double(avPlayer.rate) : 0
        timeAnchor = TimeAnchor(position: seconds, date: Date(), rate: rate)
    }

    // MARK: - Audio session

    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
        #endif
    }

    private func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    // A call or another app took the audio; remember the intent so it can come back.
                    self.resumeAfterInterruption = self.wantsToPlay
                    self.avPlayer.pause()
                    self.sampleTime()
                case .ended:
                    if self.resumeAfterInterruption, options.contains(.shouldResume) { self.resume() } else if self.resumeAfterInterruption { self.pause() }
                    self.resumeAfterInterruption = false
                default: break
                }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                // Headphones out: stop rather than play out loud.
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        }
        #endif
    }

    private var resumeAfterInterruption = false

    // MARK: - Now Playing and remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        center.pauseCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.togglePlayPause() }; return .success }
        center.nextTrackCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { @Sendable [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(to: time) }
            return .success
        }
        center.changeShuffleModeCommand.addTarget { @Sendable [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let on = event.shuffleType != .off
            Task { @MainActor in self?.setShuffle(on) }
            return .success
        }
        center.changeRepeatModeCommand.addTarget { @Sendable [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: RepeatMode = switch event.repeatType { case .one: .one; case .all: .all; default: .off }
            Task { @MainActor in self?.setRepeat(mode) }
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    private func updateRemoteCommandState() {
        let center = MPRemoteCommandCenter.shared()
        center.changeShuffleModeCommand.currentShuffleType = queue.isShuffled ? .items : .off
        center.changeRepeatModeCommand.currentRepeatType = switch queue.repeatMode { case .off: .off; case .all: .all; case .one: .one }
    }

    private func updateNowPlaying() {
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard let song = queue.current?.song else {
            infoCenter.nowPlayingInfo = nil
            return
        }
        var info = infoCenter.nowPlayingInfo ?? [:]
        if info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String != song.id {
            info = [:]
            nowPlayingArtworkFor = nil
        }
        info[MPNowPlayingInfoPropertyExternalContentIdentifier] = song.id
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artistLine
        info[MPMediaItemPropertyAlbumTitle] = song.album?.title
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position()
        info[MPNowPlayingInfoPropertyPlaybackRate] = timeAnchor.rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = wantsToPlay ? .playing : .paused
        updateRemoteCommandState()

        if let url = song.artwork?.url(pixels: 600), nowPlayingArtworkFor != url, let loader = artworkLoader {
            nowPlayingArtworkFor = url
            let songId = song.id
            Task {
                guard let artwork = await loader(url) else { return }
                guard queue.current?.song.id == songId else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    // MARK: - Persistence

    private struct Saved: Codable {
        var queue: PlayQueue
        var position: TimeInterval
    }

    private var queueFile: URL? { storage?.appending(path: "queue.json") }

    /// Save the queue so the app reopens where it was.
    public func persistQueue() {
        guard let queueFile else { return }
        let saved = Saved(queue: queue, position: position())
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: queueFile, options: .atomic) }
    }

    private func persistSettings() {
        UserDefaults.standard.set(autoplay, forKey: "koda.autoplay")
    }

    /// The last queue comes back paused; nothing loads until play is pressed.
    private func restore() {
        if UserDefaults.standard.object(forKey: "koda.autoplay") != nil {
            autoplay = UserDefaults.standard.bool(forKey: "koda.autoplay")
        }
        guard let queueFile, let data = try? Data(contentsOf: queueFile),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.queue.current != nil else { return }
        queue = saved.queue
        duration = queue.current?.song.duration ?? 0
        timeAnchor = TimeAnchor(position: saved.position, date: Date(), rate: 0)
        phase = .idle
        updateNowPlaying()
    }
}
