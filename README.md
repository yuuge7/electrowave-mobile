# Electrowave Mobile

A local music player for Android, built with Flutter. Your files, on your phone — no streaming, no accounts, no telemetry.

## Features

- **Library** — pick a folder and it scans recursively for audio (mp3, flac, m4a, ogg, wav), reading tags and embedded album art. Search by title, artist, or album; sort by title, artist, date added, or play count. Removing a track is a soft delete, so play history survives.
- **Playback** — powered by `media_kit`. Play/pause, seek, next/previous, shuffle, repeat (off / all / one). Mini player above the navigation bar expands to a full now-playing screen.
- **Background playback** — keeps playing with the screen off, with a media notification, lock screen controls, audio focus handling, and headset/bluetooth button support.
- **Queue system** — playing a track from any list sets that list as the playback context; a manual queue (*Play next* / *Add to queue*) always takes priority. Reorder or remove from the queue screen.
- **Sleep timer** — 15/30/45/60 min presets, custom duration, or "end of current track". Countdown chip on the now-playing screen; cancel or extend (+15 min) anytime. Fades out before pausing.
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
- **Release signing**: keystore at `android/app/electrowave-release.jks` plus `android/key.properties`, both gitignored. Builds fall back to the debug key when `key.properties` is absent; CI restores both from GitHub secrets (`.github/workflows/release.yml`).
- Run `dart run build_runner build` after editing the drift schema in `lib/core/database/database.dart`.

## License

See [LICENSE](LICENSE).
