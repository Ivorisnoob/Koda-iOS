# Koda — map for Claude

A YouTube Music client in SwiftUI: an iPhone app plus a Mac Catalyst app (Mac idiom, macOS 26, universal). iOS 26 deployment target, Liquid Glass. Swift 6, `@Observable`, no third-party packages.

## Rules

- **Keep this file current.** Every change that adds a feature, file, setting, persisted key or non-obvious decision adds or updates a short line here: where it lives and how it works. Short entries, no history; history goes in commits, Mac design notes in `docs/mac.md`.
- **SwiftUI defaults first.** System controls, materials, transitions and APIs (`safeAreaBar`, `scrollEdgeEffectStyle`, `navigationTransition(.zoom)`, `ContentUnavailableView`, `.glassEffect`) over hand-rolled ones. No hacks to fight the framework.
- **iPhone UI stays as it is** unless the task is about it. The Mac has its own views; shared screens branch with `if Platform.isMac { macBody } else { phoneBody }`.
- **Building:** the dev Mac is a slow Intel machine. Quick checks only: `swift build`/`swift test` in `KodaCore`, or an incremental Debug Catalyst build into `build/macdbg`. Full builds run on GitHub Actions when `beta` is pushed (`.github/workflows/build.yml`: `build` → unsigned .ipa, `mac` → universal Koda.dmg).
- New `.swift` files are picked up automatically (synchronized folders); no pbxproj edits needed.
- The app target defaults to **MainActor isolation**: value types used off the main actor (Codable snapshots, anything sent to `Task.detached`) need `nonisolated struct/enum`.
- Comments explain *why*, in plain sentences, matching the existing style.

## Layout

```
KodaCore/            Swift package: everything below the UI (has tests)
  InnerTube/         YouTubeMusic API (InnerTube.swift), PageCache (10-min in-memory page cache), StreamResolver, VisitorIdentity
  Parsing/           JSON → models (Pages.swift, Rows.swift); Rows.isVideo detects music videos
  Models/            Song, Artwork, *Summary, Shelf, MusicItem, Mood (all Codable), YouTubeLink
  Playback/          Player (AVPlayer, queue, remote commands, persistence), PlayQueue, CachingLoader
  Library/           Library (liked, recent, stats, user playlists → library.json), Taste (mix seeds)
  Storage/           AudioStore (song cache + downloads), Downloads
  Lyrics/, LastFM/   lyrics sources + parsing; Last.fm scrobbling
Koda/                the app target
  App/               KodaApp (+ .appEnvironment), AppModel (long-lived objects), AppSettings (UserDefaults prefs),
                     Route (every pushable page), RootView (iPhone tabs), MacShell (Platform.isMac, MacPlayerBar, menu bar KodaCommands),
                     Snapshot (on-disk JSON of pages for cold launch)
  Screens/           iPhone screens (+ Mac bodies of shared ones): Home (HomeModel), Search (SearchModel), Album, Artist, Playlist, Settings…
  Mac/               Mac-only: MacRootView (sidebar, sections, Up Next glance), MacHomeView, MacBrowseSearch, MacComponents, MacSettingsView
  Player/            NowPlayingView (+ TransportControls), MiniPlayer (PlayPauseButton), QueuePanel, lyrics views, SleepTimer
  Components/        SongRow, Cards, ShelfView, Loading (LoadState, AsyncContent, placeholders), SongActions (SongMenuItems)
  Images/            ArtworkView, ImagePipeline (downsampled, memory + 300 MB URLCache on disk), Palette
docs/                mac.md (Mac decisions and scars), lastfm.md
```

## How things work

- **Environment:** `AppModel` owns `Player`, `Library`, `Downloads`, `LastFM`, `settings`. Views read them with `@Environment(X.self)`. Anything *presented* (sheet, cover, popover) must add `.appEnvironment(model)` or it crashes on Catalyst.
- **Settings:** add a property to `AppSettings` with a `didSet` that writes UserDefaults (`koda.*` keys), read it in `init`, then show it in both `Screens/SettingsView.swift` (iPhone Form) and `Mac/MacSettingsView.swift` (pane, `MacSettingsGroup`/`MacSettingsToggle`/`MacSettingsRow`). Player-owned prefs (autoplay, normalize, cache while streaming, volume) live on `Player`.
- **Navigation:** push with `NavigationLink(value: Route.…)`; from outside a stack use `model.open(route)`. The Mac keeps one path per sidebar section (`paths[MacSection]`); Now Playing on the Mac is `Route.nowPlaying` pushed with the zoom transition.
- **Mac toolbar:** never hide/remove the toolbar or sidebar toggle at runtime; change what the detail column shows instead (see `docs/mac.md`).
- **Loading:** pages use `LoadState` and draw their own layout redacted from a placeholder while loading (`.loadingPlaceholder()`).
- **Cold launch:** `HomeModel` restores its last `Snapshot` ("home") in `init` and refreshes in place when `needsRefresh`; Search's mood tiles restore from "moods". To make another page open from cache, give it a Codable state and use `Snapshot.load/save` the same way.
- **Artwork:** always `ArtworkView` (square crop; YouTube video thumbnails are letterboxed 4:3 and are scaled to hide the bars). Images that fill a frame go in an `.overlay` of a fixed shape so their own size never drives layout.
- **Skip buttons:** `AppSettings.showsSkipButtons` / `skipInterval` (5/10/15/30 s, `gobackward.N`/`goforward.N` symbols) → `Player.skip(by:)`. Shown in `TransportControls` (Now Playing) and `MacPlayerBar`; ⌥⌘←/→ in the Controls menu. Lock-screen skip commands stay off so next/previous remain there.
- **Sidebar foot (Mac):** `MacSidebarGlance` shows the next song and today's listening, attached with `safeAreaBar` so the list gets the system scroll-edge effect under it.
- **Persistence:** queue (`Player.persistQueue`), library JSON and audio store are flushed in `AppModel.saveState()` when the app leaves the screen.

## Checking things you can't see

Add a temporary probe behind an environment variable that writes to stderr, run the Debug Catalyst build, read the output, then remove the probe before committing.
