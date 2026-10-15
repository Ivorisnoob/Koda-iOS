# Koda for iPhone

A music player for YouTube Music, written in SwiftUI for iOS 26 with Liquid Glass. The iOS sibling of [Koda for Android](https://github.com/Ivorisnoob/Koda), music only.

Koda is an unofficial client and is not affiliated with YouTube or Google.

## What it does

- Home built around **Your Mix**, woven from radios of the artists you play most, plus Jump back in, Quick picks, your top artists, moods and new releases
- Search with suggestions, filters, voice search, and YouTube or YouTube Music links pasted straight in
- Album, artist and playlist pages; playlists of your own you can reorder, rename and fill from any song's menu
- Gapless playback in the background, lock screen and Control Center controls, AirPlay, volume normalization
- Shuffle, repeat, autoplay radio, a queue you can reorder, and a sleep timer
- Word-by-word synced lyrics from YouLyPlus and BetterLyrics, line-synced from LRCLIB, with duets, backing vocals and shareable lyric cards
- A profile with listening stats: time listened, streaks, top songs and artists
- Liked songs, saved albums, playlists and artists, history and stats, kept on the phone, with backup and restore

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
