# Idris

Audio from your own YouTube playlists — mantras, chants, calm music — and nothing else. Paste a playlist link; Idris plays only those videos, as audio, and keeps every track it plays so the next play starts instantly and works offline.

Android, sideloaded. Same design language as [Veronica](../veronica): black and white only, Doto and Inter, 1 px ink outlines, glass tab bar and sheets. The design canvas is "Idris screens" on claude.ai.

## What it does

- **Import** a public or unlisted playlist by pasting its link (no sign-in). Re-synced when the app opens and on pull to refresh: new videos show under *Recently added*, removed ones drop out. A rename in Idris survives syncs.
- **Home:** Now playing, Recently added, Recently played, Playlists.
- **Player** (full screen; Back keeps playing, *Stop session* ends it): loop one, repeat ×N (3, 9, 11, 21, 27, 54, 108 or any count, then stop or next), sleep timer (15–60 min, custom, end of track; fades out over 10 s), shuffle, reorderable queue. Lock-screen and notification controls via audio_service.
- **Quality:** Best (default) / High (~160 kbps) / Medium (~128) / Low.
- **Cache:**
  - Every played track is cached as it plays: one chunked download feeds the player *and* fills the file, so there is no second download.
  - *Pin offline* (a playlist or a track) downloads ahead and is never evicted. Pre-caching waits for Wi-Fi unless you turn that off.
  - Unpinned audio is evicted least recently played first once it passes the limit (1, 2, 5 (default), 10 GB or no limit).
- **Glyph** (Nothing phones, optional, off): a slow breathing pulse on the strip while audio plays and Idris is open. Needs Glyph debug mode, as in Veronica.

## How playback works

```
track ──► CacheManager.open
            ├─ complete file in <appSupport>/audio ──► AudioSource.file   (no network)
            └─ else resolve a stream (quality-aware), in order:
                 youtube_explode: androidVr → androidSdkless → tv → safari
                 NewPipe Extractor (YouTubeChannel.kt)
               ──► CacheDownload: 4 MB range requests into <id>.<ext>.part
               ──► CachingAudioSource (just_audio StreamAudioSource) reads the
                   .part file as it fills; a seek past the download reads that
                   range from the network directly
               ──► on completion: rename to <id>.<ext>, mark complete, evict
```

If a stream breaks mid-play, the next resolver is tried and playback resumes at the same second. The `.part` file is resumed, not restarted. When every resolver fails, Idris skips to the next track.

## Code

| Path | What |
| --- | --- |
| `lib/core/` | Veronica's design system: theme tokens, widgets, icons, progressive-blur shader |
| `lib/data/` | drift database, `Library` repository, models, Riverpod providers |
| `lib/platform/youtube.dart` | playlist fetch, stream resolvers |
| `lib/platform/quality.dart` | quality setting and stream choice (mirrored in `YouTubeChannel.kt`) |
| `lib/platform/cache_download.dart` | chunked download + streaming source |
| `lib/platform/cache_manager.dart` | cache index, pre-cache worker, eviction |
| `lib/platform/audio_handler.dart` | media service, queue, repeat, sleep, recovery |
| `lib/platform/playback_rules.dart` | what follows a finished track; shuffle |
| `lib/features/` | Home, Library, Playlist, Player (+ sheets), Settings, Onboarding |

## Build

```sh
flutter pub get
dart run build_runner build     # drift
flutter test
flutter run --release
./build_signed.sh               # signed per-ABI APKs; see .env.example
```

Pushes to `main` build and publish signed APKs (`.github/workflows/release.yml`; secrets `IDRIS_KEYSTORE_BASE64`, `IDRIS_KEYSTORE_PASSWORD`, `IDRIS_KEY_PASSWORD`, `IDRIS_KEY_ALIAS`).

## Licences

NewPipe Extractor is GPL-3.0. Doto and Inter are OFL. youtube_explode_dart is BSD-3. just_audio and audio_service are MIT.
