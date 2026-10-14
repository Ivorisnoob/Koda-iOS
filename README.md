# Koda for iPhone

A music player for YouTube Music, written in SwiftUI for iOS 26 with Liquid Glass. The iOS sibling of [Koda for Android](https://github.com/Ivorisnoob/Koda), music only.

Koda is an unofficial client and is not affiliated with YouTube or Google.

## What it does

- Home with Quick picks, moods and genres, new releases and top artists
- Search with suggestions and filters for songs, albums, artists and playlists
- Album, artist and playlist pages
- Gapless playback in the background, lock screen and Control Center controls, AirPlay
- Shuffle, repeat, autoplay radio, and a queue you can reorder
- Synced lyrics
- Liked songs, saved albums, playlists and artists, and history, kept on the phone

## Layout

| Path | What |
|---|---|
| `KodaCore/` | Swift package with no UI: InnerTube client, parsers, stream resolution, the queue and the player. Builds and tests on macOS. |
| `Koda/` | The SwiftUI app. |
| `.github/workflows/build.yml` | Runs the tests and builds an unsigned `.ipa` on every push. |

## Building

Xcode 26 or later.

```sh
cd KodaCore && swift test                                   # unit tests
KODA_LIVE=1 swift test --filter Live                        # against live YouTube, plays muted audio
xcodebuild -project Koda.xcodeproj -scheme Koda -destination 'generic/platform=iOS' build
```

## Installing

Every push builds an unsigned `Koda.ipa` (Actions tab, then the run's artifacts). Install it with AltStore, SideStore or Sideloadly, which sign it with your Apple ID. A free Apple ID's signature lasts seven days; AltStore and SideStore refresh it in the background.
