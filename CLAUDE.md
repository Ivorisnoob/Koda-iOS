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
  Library/           Library (liked, recent, stats, user playlists → library.json), Taste (mix seeds),
                     AndroidBackup (reads Koda for Android's backup zip; Library.importAndroid merges it)
  Storage/           AudioStore (song cache + downloads; completeSongs = Ready Offline), Downloads, ZipReader
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
  Intents/           KodaIntents (App Intents + App Shortcuts + Spotlight, iPhone and Mac),
                     SiriSchemas (iOS 27 audio schemas for the new Siri; only built with the iOS 27 SDK, never Catalyst)
Shared/              compiled into the app AND KodaWidgets: PlaybackIntents (PlayLikedSongs, TogglePlayback)
KodaWidgets/         widget extension (ivors.Koda.Widgets): Quick Play widget (Home/Lock Screen, Mac), Control Center controls
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
- **Crossfade:** `Player.crossfades` / `crossfadeDuration` (default on, 5 s, 1–12). With it on, the next song waits on a separate paused `AVQueuePlayer` (`standby`) instead of behind the current item; a boundary observer at end − duration calls `switchToStandby`, which retires the old player to `tail` (fading out, equal-power) and adopts the standby as `avPlayer` (`attach`/`detach` move the KVO + time observers; callbacks from a non-main player are dropped). Skips fade by `Player.skipFade` (0.6 s). AVFoundation can't move an item between players (`_attachToPlayer` throws), hence two players. Off, the old gapless queue path is unchanged. Live tests: `KODA_LIVE=1 swift test --filter LivePlayerTests`.
- **Last.fm credentials:** Keychain read returns found/missing/unreadable. Unreadable (locked device, Mac keychain locked) is *not* signed out: `connectedUser` (in lastfm.json) keeps it shown connected, plays queue, every call re-reads first, and nothing writes over the saved credentials until read (`saveCredentials(replacing:)` only for sign-in).
- **Ready Offline:** `Route.SongSource.offline` / `MacSection.offline` → `SavedSongsView` listing `AudioStore.completeSongs` (downloads + songs cached whole).
- **Android import:** Settings → Back Up and Restore → Import from Koda for Android (both platforms, `androidBackupImporter` modifier). Takes liked songs, play history (→ stats, daily listening, recent), searches, user playlists, saved albums (MPREb ids) and playlists from the active profile; skips local files. Merges; `androidPlaysImportedThrough` stops plays counting twice. Fixture is a real Java-written zip.
- **Mac window:** min 700×520. Pages that put two columns side by side switch to one under a width (`onGeometryChange` + `AnyLayout`): Home's mix/picks, search's top result, Last.fm, collection headers (smaller cover < 620), player bar (narrow < 760: 270 pt transport, speaker-only volume). Search is `.searchable(placement: .toolbar)` (top right); Home's Refresh is in its page title (⌘R), like Last.fm's Sync Now.
- **Siri / Shortcuts:** intents get the app through `@Dependency var app: AppModel` (registered in `KodaApp.init`). Audio intents run in the app, which the system starts in the background. `IntentsIndex.update` (on launch and when liked songs/playlists change) refreshes App Shortcut parameters and Spotlight. iOS 27 schema code sits in `#if canImport(MediaIntents) && !targetEnvironment(macCatalyst)` + `@available(iOS 27, *)`; schema macros wrap the schema's properties, so in an init set `id` and plain stored properties *first*. Reference: Apple's "Integrating your music app with Apple Intelligence" sample. CI's iOS job runs on `xcode-27` for this.
- **Widgets:** no App Group (the unsigned .ipa / ad-hoc .dmg can't carry one reliably), so widgets draw nothing from the app: buttons running `Shared/PlaybackIntents.swift` intents, which execute in the app (audio intents). Intents shared with the extension use `#if WIDGET_EXTENSION` (set in KodaWidgets' build settings) to stub `perform` there. Controls are iPhone-only (`#if !targetEnvironment(macCatalyst)`). A new widget needing app data would need an App Group plus entitlements in CI signing.
- **Share Lyrics:** `LyricsShareSheet` scrolls to the line it was opened from; on the Mac it has its own layout (preview left, lines right, Cancel/Copy Image/Share in the foot, `.presentationSizing(.fitted)`).
- **Persistence:** queue (`Player.persistQueue`), library JSON and audio store are flushed in `AppModel.saveState()` when the app leaves the screen.

## Testing the real (Release) builds

The optimized .ipa and .dmg come only from CI; never ship or test a local Debug build as the app.

1. Commit and `git push origin beta`. The `Build` workflow starts on its own (about 3–5 minutes).
2. Find the run: `gh run list --branch beta --limit 1` (check its title matches the commit).
3. Wait for it: `gh run watch <run-id> --exit-status` (a non-zero exit means a job failed; read `gh run view <run-id> --log-failed`).
4. Download and rename so Downloads holds just two short files, `Koda-<short-sha>.dmg` and `Koda-<short-sha>.ipa`.
   gh nests each artifact in a folder named with the full SHA, so always flatten it:
   ```sh
   sha=$(git rev-parse --short HEAD); tmp=$(mktemp -d)
   gh run download <run-id> --dir "$tmp"
   mv "$tmp"/Koda-mac-*/Koda.dmg ~/Downloads/Koda-$sha.dmg   # Mac, universal
   mv "$tmp"/Koda-[0-9a-f]*/Koda.ipa ~/Downloads/Koda-$sha.ipa # iPhone, unsigned
   rm -r "$tmp"
   ```
5. Install:
   - **Mac:** open `Koda.dmg`, drag Koda to Applications (replace the old one). It's ad-hoc signed and not notarized, so the first launch needs System Settings → Privacy & Security → **Open Anyway**.
   - **iPhone:** sideload `Koda.ipa` with AltStore, SideStore or Sideloadly; they sign it with your Apple ID.

Do this after every pushed change the user wants to try, and tell them the folder path.

## Checking things you can't see

Add a temporary probe behind an environment variable that writes to stderr, run the Debug Catalyst build, read the output, then remove the probe before committing.
