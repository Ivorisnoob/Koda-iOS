import KodaCore
import MediaPlayer
import SwiftUI

/// The app's long-lived objects, shared through the environment.
@MainActor
@Observable
final class AppModel {
    let music: YouTubeMusic
    let player: Player
    let library: Library
    let lyrics = LyricsClient()
    let sleepTimer: SleepTimer
    let profile: Profile

    var isNowPlayingPresented = false
    /// Set to switch tabs from anywhere, e.g. "Go to artist" inside Now Playing.
    var selectedTab: AppTab = .home
    /// A page to open on the current tab's stack.
    var pendingRoute: Route?
    /// Songs waiting for the listener to pick a playlist for them.
    var playlistTarget: PlaylistTarget?
    /// A shared link that could not be opened, shown as an alert.
    var linkError: String?

    struct PlaylistTarget: Identifiable {
        let id = UUID()
        let songs: [Song]
    }

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Koda")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        music = YouTubeMusic()
        player = Player(music: music, storageDirectory: directory)
        library = Library(directory: directory)
        sleepTimer = SleepTimer(player: player)
        profile = Profile(directory: directory)
        player.onSongStarted = { [library] song in library.recordPlay(song) }
        player.onListened = { [library] song, seconds in library.addListening(seconds, to: song) }
        player.artworkLoader = { @MainActor url in
            guard let image = await ImagePipeline.shared.image(url, pixels: 600) else { return nil }
            return ImagePipeline.nowPlayingArtwork(image)
        }
    }

    /// Open a page from outside a navigation stack: closes Now Playing and pushes it on the current tab.
    func open(_ route: Route) {
        isNowPlayingPresented = false
        pendingRoute = route
    }

    func addToPlaylist(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        playlistTarget = PlaylistTarget(songs: songs)
    }

    /// Open a YouTube, YouTube Music or koda:// link: a song plays with its radio, anything else opens its page.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = YouTubeLink(url) else { return false }
        openLink(link)
        return true
    }

    func openLink(_ link: YouTubeLink) {
        switch link {
        case .song(let videoId):
            Task { await playLinkedSong(videoId) }
        case .album(let browseId):
            open(.album(AlbumSummary(id: browseId, title: "", artistLine: "")))
        case .playlist(let id):
            open(.playlist(PlaylistSummary(id: id, title: "")))
        case .artist(let channelId):
            open(.artist(ArtistSummary(id: channelId, name: "")))
        }
    }

    /// A video id alone carries no title or artist; its radio starts with the song itself, which has both.
    private func playLinkedSong(_ videoId: String) async {
        do {
            let radio = try await music.radio(for: videoId)
            guard let seed = radio.songs.first(where: { $0.id == videoId }) ?? radio.songs.first else {
                linkError = "That song isn't available."
                return
            }
            player.play([seed] + radio.songs.filter { $0.id != seed.id })
            isNowPlayingPresented = true
        } catch {
            linkError = error.friendlyMessage
        }
    }

    /// The app is leaving the screen: write what is only kept in memory.
    func saveState() {
        player.persistQueue()
        library.flush()
    }
}

enum AppTab: Hashable {
    case home, library, search
}
