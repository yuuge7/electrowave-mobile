# Electrowave Mobile

A local music player for Android, built with Flutter. Your files, on your phone — no streaming, no accounts, no telemetry.

## Features

- **Library** — pick a folder and it scans recursively for audio (mp3, flac, m4a, ogg, wav), reading tags, track/disc numbers and album art. Art comes from the embedded tag, falling back to a `cover.jpg` / `folder.jpg` sitting next to the files. Browse by **tracks, albums, artists or folders**; search by title, artist, or album; sort by title, artist, date added, or play count.
- **Smart lists** — Favorites, Recently added, Recently played and Most played, generated from listening data.
- **Favorites** — heart any track from the now-playing screen or its context menu.
- **Tag editor** — fix title, artist, album, genre, track/disc number and year in-app. Writes the file's tags and the library row, so a rescan won't undo your edit.
- **Removed tracks** — removing a track is a soft delete, so play history survives; Settings → Removed tracks restores it or deletes it for good. Audio files on disk are never touched.
- **Equalizer** — 5-band EQ (±12 dB) with presets, plus ReplayGain volume normalization per track or per album.
- **Playback speed** — 0.5× to 2×, persisted and re-applied to every track.
- **Appearance** — light / dark / follow-system, and optional Material You colors from your wallpaper.
- **Home screen widget** — current track and previous / play-pause / next without unlocking.
- **Playback** — powered by `media_kit`. Play/pause, seek, next/previous, shuffle, repeat (off / all / one). Mini player above the navigation bar expands to a full now-playing screen.
- **Background playback** — keeps playing with the screen off, with a media notification, lock screen controls, audio focus handling, and headset/bluetooth button support.
- **Queue system** — playing a track from any list sets that list as the playback context; a manual queue (*Play next* / *Add to queue*) always takes priority. Reorder or remove from the queue screen.
- **Sleep timer** — 15/30/45/60 min presets, custom duration, or "end of current track". Countdown chip on the now-playing screen; cancel or extend (+15 min) anytime. Fades out before pausing.
- **Stop when unattended** — playback stops after a chosen stretch with no interaction at all (Settings → Playback: off / 30 min / 1 / 2 / 4 / 8 h, default 2 h). Any touch in the app, notification, widget or headset button resets it; automatic track advances do not.
- **Playlists** — create, rename, reorder; add tracks from any track's context menu.
- **Play tracking** — a listen is logged once a track crosses 25% played, feeding play counts and last-played dates.
- **Stats ("Wrapped")** — total listening time, top tracks, and top artists, filterable by month, year, or all time.
- **Backup & restore** — export the SQLite database anywhere; imports are staged and applied safely on the next launch.

## Permissions

- **Music & audio access** (`READ_MEDIA_AUDIO`, Android 13+; `READ_EXTERNAL_STORAGE` on older versions) — required to scan your music. Nothing leaves the device.
- **Notifications** — for the playback controls notification.
- **Ignore battery optimizations** — optional, requested from Settings → Playback. Aggressive OEM power managers (Xiaomi, Samsung, Huawei…) kill background playback without it.

## Building from source

Requirements: Flutter (stable channel) with the Android toolchain (`flutter doctor` should be green).

```bash
flutter pub get
dart run build_runner build   # drift codegen
flutter build apk --release
```

APK lands in `build/app/outputs/flutter-apk/app-release.apk`.

## Tech stack

Flutter · Riverpod · go_router · media_kit · drift/SQLite · audio_metadata_reader · audio_service

## Project structure

```
lib/
├── core/database/      # drift schema: tracks, playback history, playlists
├── features/
│   ├── library/        # scanning, track list, search/sort
│   ├── player/         # playback, queue, sleep timer, scrobbling
│   ├── playlists/
│   ├── settings/       # backup/restore
│   └── stats/
└── shared/widgets/     # nav shell, mini player
```

## Development notes

Non-obvious constraints — breaking these produces bugs that only show up after long real-world use:

- **`androidStopForegroundOnPause` must stay `false`** (`main.dart`). media_kit emits a brief `playing=false` at every track transition; leaving the foreground state there releases audio_service's wake lock exactly when Dart needs CPU to open the next file, so playback dies mid-queue once the device is dozing. The handler compensates with a 15-minute idle-stop timer. `androidNotificationOngoing` must be `false` while this is.
- **Never broadcast playback state on position ticks** (`audio_handler.dart`). Android extrapolates notification progress from `updatePosition`/`updateTime`/`speed`, so `_broadcast` is event-driven only (play/pause, buffering, seek).
- **Album art decodes must pass a bounded `cacheWidth`** (`ArtThumb`). A full-resolution decode of oversized embedded art fails where a downscaled decode of the same file succeeds — that's what makes large art fall back to the gray placeholder.
- **`android/gradle.properties` must keep `android.builtInKotlin=false`**, and file_picker stays pinned to 10.x: 11.x requires built-in Kotlin while audio_service and others still apply the external Kotlin plugin, and mixing them fails the Gradle build.
- **Import collisions**: media_kit exports its own `Track` — import it with `hide Track` where the drift `Track` is in scope. Flutter's material library exports `RepeatMode`, so `now_playing_screen.dart` imports material with `hide RepeatMode`.
- **Bootstrap order** in `main.dart`: MediaKit init → staged backup import (must precede opening the DB) → `AppDatabase` → `AudioService.init` → `ProviderScope` overrides.
- **Release signing**: keystore at `android/app/electrowave-release.jks` (PKCS12, alias `electrowave`) plus `android/key.properties`, both gitignored. Builds fall back to the debug key when `key.properties` is absent — so a local `flutter build apk --release` succeeding does **not** prove the release key works.

  CI restores both from the `KEYSTORE_BASE64` and `KEYSTORE_PASSWORD` secrets. To regenerate `KEYSTORE_BASE64` (single line, no wrapping, straight to the clipboard so it never lands in a file or shell history):

  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\electrowave-release.jks")) | Set-Clipboard
  ```

  Paste that as the secret value. Do **not** use `certutil -encode`: it wraps the output in `-----BEGIN CERTIFICATE-----` lines, which `base64 -d` rejects. The workflow verifies the restored keystore with `keytool` and prints its size and SHA-256, so a mismatch fails at the restore step with a readable message instead of surfacing as a DER/ASN.1 parse error (`Tag number over 30 is not supported`) inside `:app:packageRelease`.
- Run `dart run build_runner build` after editing the drift schema in `lib/core/database/database.dart`. The schema is at **v2**; `MigrationStrategy` adds `isFavorite`, `trackNumber`, `discNumber` and `year`, so existing installs upgrade in place.
- **EQ and ReplayGain run inside libmpv, not Android.** media_kit doesn't expose the Android audio session id, so the platform `AudioEffect` API (Equalizer/BassBoost) is unreachable. `applyAudioSettings` builds an mpv `af` chain of `equalizer` filters and sets mpv's own `replaygain` property instead — same behaviour on every platform, no session id needed.
- Playback speed must be re-applied after every `Player.open()`; mpv resets it per file. The handler keeps `_desiredRate` for exactly that.
- Albums are grouped by **album name alone**. Grouping by (album, artist) splits compilations and albums with featured guests into one row per artist; the artist column shows the single artist when there is one and 'Various artists' otherwise.

### Not implemented: gapless playback / crossfade

`_loadAndPlay` opens one file at a time, so there is a short gap at every track change. Closing it properly means handing the queue to mpv's own playlist (`gapless-audio` only applies to mpv-internal transitions) while `PlayerController` still owns manual-queue priority, shuffle order and repeat — two things advancing the same queue, with the resync races that implies. That is the same area as the "playback dies mid-queue" bug fixed earlier, and it can't be validated without listening to a real device through sleep/doze cycles, so it was left alone deliberately rather than landed untested.

## License

See [LICENSE](LICENSE).
