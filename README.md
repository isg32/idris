<div align="center">

<img src="assets/icon/icon-base.png" alt="Idris: flowers in an envelope" width="120">

# Idris

**Your mantras and calm music, from your own YouTube playlists — and nothing else.**

![Version](https://img.shields.io/badge/version-2.0.0-000000?style=flat-square)
![Release](https://img.shields.io/github/v/release/isg32/idris?style=flat-square&color=000000&label=release)
![Flutter](https://img.shields.io/badge/Flutter-3.47-000000?style=flat-square&logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Android%20%C2%B7%20Linux-000000?style=flat-square&logo=android&logoColor=white)
![License](https://img.shields.io/badge/license-GPL--3.0-000000?style=flat-square)

</div>

<p align="center">
  <img src="docs/screenshots/home-player.png" alt="Idris's Home with the mini player, and the full player with blurred artwork behind it" width="100%">
</p>

---

## Why Idris

> Idris is a last name of someone who belongs to my heart, a very dear person to me. it was tragic but well, here we are.

YouTube is where the chants, mantras and calm music live, but opening YouTube means recommendations, Shorts and comments. Idris plays **only the playlists you give it**, as audio, in a quiet black-and-white app.

Paste a playlist link once. Idris keeps it in sync, and every track it plays is kept on the phone, so the next play starts instantly and works without a network.

### Principles

| Principle | What it means in practice |
| --- | --- |
| **Only your playlists** | No search, no feed, no suggestions. Idris plays the videos in the playlists you import, as audio. |
| **No buffering the second time** | One download both plays a track and caches it. Played tracks are on the phone for good, until the cache needs the room. |
| **Offline and private** | No account and no sign-in. Nothing is collected or sent anywhere but YouTube. |
| **Calm** | Veronica's design language: pure black and white, dot-matrix type, 1 px ink outlines, glass. Artwork is an experimental, optional exception. |

Idris is a personal, sideloaded app, not distributed through the Play Store.

## Features

| Area | What it does |
| --- | --- |
| **Playlists** | Paste a public or unlisted playlist link (no sign-in). Re-synced when the app opens and on pull to refresh: new videos show under *Recently added*, removed ones drop out. A rename in Idris survives syncs. |
| **On this phone** | Music from folders you choose on the phone, in one list at the top of Library: titles, artists and covers read from the files, played straight from them (never cached, no network). Pull down to pick up new files; removing a folder only takes it out of Idris. Uses Android's folder picker, so no storage permission. |
| **Home** | Recently added, recently played and your playlists. |
| **Player** | Full screen, growing out of the mini player and shrinking back into it with a swipe down. Loop (off, playlist, one track), repeat a track ×N (3 to 1008, then stop or next), sleep timer (15 to 60 min, custom or end of track, fading out), shuffle and a reorderable queue. |
| **Mini player** | Docked above the tab bar and on playlist pages, as in Spotify and Apple Music. |
| **Volume keys** | While music plays, even with the screen off or another app in front: double-tap or hold Volume up for the next track, Volume down for the previous; a single tap still changes the volume. Off in Settings › Playback. |
| **Media controls** | Background playback with the notification, lock screen, quick-settings player and headset buttons. |
| **Quality** | Best (default), High (~160 kbps), Medium (~128 kbps) or Low. |
| **Cache** | Every played track is kept. *Pin offline* (a playlist or a track) downloads ahead, on Wi-Fi by default, and is never removed. Unpinned audio past the limit (1, 2, 5 or 10 GB, or none) goes least recently played first. To free space yourself: *Remove from cache* on a track, *Remove downloads* on a playlist (which also stops keeping it offline), or *Clear auto cache* in Settings. |
| **Covers** | Every track shows its YouTube picture, cropped square, in lists, on Home and in the mini player, and blurred behind the player (Settings › Artwork, on by default). A playlist's cover is a mosaic of its first four tracks. Long-press a track or playlist (or tap a playlist's cover) to choose a picture from the phone instead; it's copied into Idris. All saved on the phone, so they show offline. |
| **Crash reports** | An unexpected error shows a calm popup with the log, *Copy log* and *Save to Downloads*. A crash on the Android side is shown on the next launch. |
| **Updates** | Idris updates itself from GitHub Releases: it checks at launch and every 6 hours (or from *Settings › Check for updates*), shows a card on Home and in Settings, downloads with progress (resuming after a drop), checks the size, SHA-256 and signer, and installs through Android's PackageInstaller. After the first update, Android installs the next ones without its confirm screen. *What's new* shows once afterwards. |
| **Linux** | The same app on a Linux desktop, from the same code: YouTube streams found by the same NewPipe extractor (a small Java helper), audio through libmpv, and "On this computer" for folders of music on disk. |
| **Layouts** | Three, by window size: mobile (tab bar and mini player), tablet (a rail of sections) and desktop (a sidebar with the playlists, pages in columns, a now-playing bar). |
| **Glyph** | Optional, on Nothing phones: a slow breathing pulse on the strip while audio plays. |

---

## Architecture

Idris is a Flutter app (Cupertino widgets only, no Material) for Android and Linux. On Android a thin native Kotlin layer runs NewPipe's extractor, the folder picker, the updater and crash files; on Linux NewPipe's extractor runs as a small Java helper (`linux/extractor`) and audio plays through libmpv.

```mermaid
flowchart TB
    subgraph UI["Presentation (lib/features, lib/app)"]
        pages["Home, Library, Playlist, Player, Settings, About"]
        mini["Mini player and player panel"]
    end
    subgraph State["State (Riverpod)"]
        providers["Stream providers over the library and the player"]
    end
    subgraph Data["Data (lib/data)"]
        library["Library: drift (SQLite)"]
    end
    subgraph Platform["Platform (lib/platform)"]
        handler["IdrisAudioHandler: audio_service + just_audio"]
        cache["CacheManager: chunked download, pre-cache, eviction"]
        yt["YouTube: playlist reader, stream resolvers"]
        crash["CrashLog"]
        updater["Updater: OTA from GitHub Releases"]
    end
    pages --> providers --> library
    mini --> providers --> handler
    handler --> cache --> yt
```

**How a track plays.**

```
track ──► CacheManager.open
            ├─ complete file in <appSupport>/audio ──► AudioSource.file   (no network)
            └─ else resolve a stream (quality-aware), in order, using the
               first whose link YouTube actually serves:
                 NewPipe Extractor (YouTubeChannel.kt)
                 youtube_explode: androidVr → androidSdkless → tv → safari
               ──► CacheDownload: 1 MB range requests (YouTube refuses more)
                   into <id>.<ext>.part
               ──► CachingAudioSource (just_audio StreamAudioSource) reads the
                   .part file as it fills; a seek past the download reads that
                   range from the network directly
               ──► on completion: rename to <id>.<ext>, mark complete, evict
```

If a stream breaks mid-play, the next resolver is tried and playback resumes at the same second. The `.part` file is resumed, not restarted. All YouTube traffic leaves by one network route (IPv6 when the phone has a public address, else IPv4), because stream links are signed for the address that asked for them.

**Playlists.** YouTube's current playlist pages list videos as `lockupViewModel` items, which youtube_explode doesn't read yet, so `PlaylistScraper` reads them (and the older format), following continuation pages.

### Enforced rules

Checked by tests on every run:

- **Two colours.** Colours may only be created in `lib/core/theme/v_colors.dart`, and importing Material fails the build.
- **Playback rules:** loop, repeat counts and the sleep timer's *end of track*.
- **Caching:** range-chunked downloads, reading while downloading, far seeks, resuming, eviction order (pinned never evicted).
- **Library sync:** added and removed videos, renames kept, pinned sets, export round-trip.
- **Playlist reading** in YouTube's current and older formats.
- **Updates:** finding, downloading, resuming, rejecting a damaged or differently signed APK, the install permission, the 6-hour check, *What's new* once; and the version in About matching `pubspec.yaml`.

---

## Project structure

| Path | What |
| --- | --- |
| `lib/core/` | Veronica's design system: theme tokens, widgets, icons, progressive-blur shader |
| `lib/data/` | drift database, `Library` repository, models, Riverpod providers |
| `lib/platform/youtube.dart` | playlist fetch, stream resolvers |
| `lib/platform/playlist_scraper.dart` | reads playlist pages (YouTube's current format) |
| `lib/platform/net.dart` | one IPv6/IPv4 route for all YouTube traffic |
| `lib/platform/quality.dart` | quality setting and stream choice (mirrored in `YouTubeChannel.kt`) |
| `lib/platform/cache_download.dart` | chunked download + streaming source |
| `lib/platform/cache_manager.dart` | cache index, artwork, pre-cache worker, eviction |
| `lib/platform/audio_handler.dart` | media service, queue, loop, repeat, sleep, recovery |
| `lib/platform/playback_rules.dart` | what follows a finished track; shuffle |
| `lib/platform/volume_keys.dart` | tells a volume-key tap from a hold |
| `lib/platform/crash_log.dart` | rolling log, error hooks, crash reports |
| `lib/platform/covers.dart` | covers the user chose, copied into the app |
| `lib/platform/local_music.dart` | "On this phone": chosen folders, scanning, `local:` tracks (with `LocalMusic.kt`) |
| `lib/platform/updater.dart` | over-the-air updates: check, download, verify, install (with `updater_channel.dart`) |
| `lib/features/` | Home, Library, Playlist, Player (panel, sheets, mini player), Settings, About, Onboarding |
| `android/app/src/main/kotlin/` | `YouTubeChannel` (NewPipe), `CrashFiles` (native crashes, Downloads), `Updater` (PackageInstaller), `LocalMusic` (folder picker, tags, embedded art) |
| `lib/core/layout.dart`, `lib/app/desktop.dart` | the three layouts by window size; the tablet and desktop frame (sidebar or rail, now-playing bar) |
| `lib/platform/desktop_extractor.dart`, `linux/extractor/` | NewPipe on Linux: the Java helper and how Idris talks to it |
| `linux/` | the Linux desktop runner |
| `tool/live_playlist_test.dart` | a by-hand check against real YouTube playlists |

---

## Getting started

### Requirements

- Flutter 3.47 or later (Dart 3.13)
- Android SDK 36 and JDK 17
- Any recent Android phone; a Nothing phone for the Glyph pulse
- For Linux: GTK 3, libmpv, clang, CMake and Ninja (e.g. `gtk3 mpv clang cmake ninja` on Arch)

### Build and run

```sh
flutter pub get
dart run build_runner build        # drift code generation
flutter analyze
flutter test
flutter run                        # with the phone connected over USB debugging
```

On Linux:

```sh
./android/gradlew -p linux/extractor installDist   # the NewPipe helper
flutter run -d linux                               # run from the repo root
```

### Signed releases

Release APKs are signed with a key that never enters the repository.

- **Locally:** copy `.env.example` to `.env`, which is gitignored. Put the keystore in it as base64 (`base64 -w0 release-key.jks`) along with its passwords, then run `./build_signed.sh`. The keystore is decoded to a temporary file for the build and deleted afterwards.
- **On GitHub:** every push to `main` runs `.github/workflows/release.yml`. It builds, tests and signs the APKs and publishes them as a release, with an `update.json` that installed copies read to update themselves. Set `IDRIS_KEYSTORE_BASE64`, `IDRIS_KEYSTORE_PASSWORD`, `IDRIS_KEY_PASSWORD` and, optionally, `IDRIS_KEY_ALIAS` as secrets in a `deployment` environment.

Without these settings, release builds fall back to the debug key.

### Over-the-air updates

**Bump the version on every push to `main`**, in `pubspec.yaml` (`version: 1.2.0+8`: name and build number) and `kAppVersion` in `lib/features/settings/about_page.dart`; `test/version_test.dart` checks they agree. `--split-per-abi` adds 1000 × the ABI to the build number (build 8 is `2008` on arm64-v8a), and CI **refuses to publish** a release whose arm64 versionCode isn't above the last one's, since no phone could install it.

Each release carries `update.json` (at `releases/latest/download/update.json`): every APK's URL, size, SHA-256 and versionCode (read from the APK with `aapt2`), and the commit subjects since the last release as *What's new*.

```
check update.json ──► newer versionCode for this ABI? ──► card on Home and in Settings
  ──► download (Range resume) ──► verify size, SHA-256, signer, versionCode
  ──► "Install unknown apps" (asked once) ──► PackageInstaller session
  ──► Idris is replaced ──► "Idris updated to X" notification, What's new on next launch
```

- Android closes the running app while it replaces it, so playback stops for the install; it's back with one tap on the notification.
- An update must be signed with the same key as the installed app. A copy signed with another key (a debug build) is told to reinstall once from GitHub.
- Copies older than 1.2.0 have no updater: install 1.2.0 by hand once, and later versions come by themselves.
- To test against a local server: `flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define=IDRIS_UPDATE_URL=http://127.0.0.1:8765/update.json` and `adb reverse tcp:8765 tcp:8765`. The server must support Range requests.

### Glyph (optional)

On Nothing phones, the breathing pulse may need Glyph debug mode, which switches itself off after 48 hours:

```sh
adb shell settings put global nt_glyph_interface_debug_enable 1
```

### Installing a release

Signed APKs are attached to every [release](https://github.com/isg32/idris/releases). For most phones, use `app-arm64-v8a-release.apk`. Everything Idris keeps stays on the phone.

---

## Development

- **Commits.** History is linear on `main`; each commit is one change with a message that says why, and passes `flutter analyze` and `flutter test`.
- **Live check.** `flutter test tool/live_playlist_test.dart --dart-define=PLAYLISTS=<id>,<id>` reads real playlists, for when YouTube changes its pages.
- **App icon.** Sources are in `assets/icon/`. Run `dart run flutter_launcher_icons` after changing them.
- **Design.** The screens were designed on the "Idris screens" canvas in Claude Design, in Veronica's design language.

---

## License

Copyright (C) 2026 Sapan Gajjar

Idris is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License v3.0](LICENSE) as published by the Free Software Foundation. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) for details.

Bundled third-party code and assets keep their own licences: NewPipe Extractor (GPL-3.0), and Doto and Inter under the SIL Open Font License ([`assets/fonts/`](assets/fonts/)).
