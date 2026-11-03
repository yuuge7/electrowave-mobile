# Android implementation and validation

Validated 3 November 2026. The requested scope is Android. Only the Android platform scaffold is retained.

All 40 items in `ideas.md` have implementations. The checks below distinguish emulator coverage from the physical-device checks requested by section 6 of that file.

## Automated checks

- `flutter analyze`: no issues.
- `flutter test --reporter expanded`: 243 unit/widget tests passed.
- Android integration: `integration_test/app_test.dart`, driven by `test_driver/integration_test.dart`, passed on the API 36 x86_64 Medium Phone emulator.
- The Android integration library contains **10,053 tracks**. The independent indexed-search test contains **10,500 tracks**. Track rows are built lazily. Search returned a single matching track in 11-25 ms across emulator runs; this is an observed sample, not a device-independent performance guarantee.
- Integration exercises all six library tabs, bulk selection, all six settings pages, listening patterns, native waveform/loudness decoding, unchanged-file scan skipping, scan cancellation, private-session accounting, paused-track favourite updates, EQ/mono/crossfeed playback, manual queue priority, queue clearing and two-track gapless transitions.
- The emulator power harness switches the screen off and forces deep idle during a 40-second repeat/transition test. It restores battery and display state afterward. The observed forced-doze interval was 40.86 seconds. The mpv playlist is asserted to contain at most two entries throughout.
- Existing overflow checks cover short/small/regular phone sizes and text scales through 2.0.

Local toolchain: Flutter 3.47.0 / Dart 3.13.0, Windows host. The release workflow uses its existing Flutter 3.44.4 Android toolchain. Its Ubuntu runner is a build host; it produces only an Android APK. CI now gates that build on analysis and tests.

## Coverage of the ideas

| Items | Implementation | Verification |
| --- | --- | --- |
| 1–3: safe, validated, complete backups | Versioned gzip `.ewbackup`; SQLite snapshot, settings, EQ, queue, folders and cached art; pre-import safety bundle; journaled replacement | Backup round trips, default-state replacement, undo, corrupted/foreign/future-schema/path traversal rejection, interrupted-journal rollback |
| 4: new-phone restore | Relink missing paths by unambiguous suffix before tag matching; preserve row IDs, history and playlists | Relink regression test; cached artwork sandbox relocation in backup tests |
| 5: weekly automatic backups | Android persisted document-tree grant and persisted weekly job; retain five; app-use fallback and private recovery copy | Forced native jobs; exactly five completed bundles, all decompressed and SQLite integrity checked |
| 6: saved folders | Multiple folders, saved sort and direction | Emulator scan/restart; complete backup round trip |
| 7–8: diagnostics and health recovery | Bounded local Dart/native logs, file export, startup database verification and recovery screen | Emulator deliberately damaged app-owned QA database; recovery restored 14 tracks and preserved the damaged original |
| 9–11: incremental/cancellable/background-tab scans | File size/date fingerprints, progress/count/folder, cancel, persistent scan controller | Native PCM scan; second scan skips all three unchanged files; cancellation; shell-level progress |
| 12–14: large-library navigation/search | A–Z rails for tracks/albums/artists; FTS5 with update triggers; indexes and lazy lists | 10,053-track emulator navigation and 10,500-track query/update/delete checks |
| 15–17: selection, reverse sort, queue actions | Bulk queue/playlist/tag/hide actions; remembered direction; save queue as playlist and clear | Emulator selection and queue clear/priority checks; playlist/database and overflow tests |
| 18–20: album artists, summary, genres/years | Tagged album-artist groups; untagged compilation fallback; size/formats/duration; genre/year/decade views | Album grouping regression; emulator library tabs and settings Library page |
| 21–22: portable playlist/stats files | M3U/M3U8 path matching and unresolved count; CSV/JSON stats export | Unicode/duration tests; release imports 2 matches plus 1 unresolved path, exports M3U8; CSV/JSON exports each verified with 14 tracks |
| 23–25: settings, About, private sessions | Six settings pages; native version/licence/offline statement; suppress plays, time, starts and skips | Emulator settings navigation/About screenshot; private-session database assertions |
| 26–29: Android controls | Shuffle/Resume/Favourites shortcuts; play/pause tile; 2×2 art and 4×2 progress/favourite widgets; monochrome icon | Shortcuts registered and actions launched; live tile label/playback checks; both widgets pinned and rendered with current artwork; Android resource build |
| 30–31: audio controls | Ten mpv EQ bands, named presets and output profiles; mono and local stereo crossfeed | Emulator plays decoded PCM through EQ, mono and crossfeed; EQ UI screenshot; native speaker-route check |
| 32: stats extras | Local-hour measured time, genres, forgotten favourites, starts/skips | Hour-boundary, genre, skip-counter and forgotten-favourite age tests; emulator screen; lazy rows |
| 33–35: build and database safeguards | CI analysis/test gates; historical migration fixtures; smart-rule tests | Real v1–v5 schemas upgrade to v6 with history/playlists intact; rule combinations, sort, limits, invalid values and hidden rows |
| 36: gapless | Current plus staged successor only; Dart owns queue/repeat/shuffle/sleep decisions; opt-in | Native transitions, queue priority and clear; screen-off/deep-idle repeat test |
| 37: waveform | 256 decoded peak bins behind accessible seek slider | Known-amplitude PCM waveform assertions and native decoder playback |
| 38: ratings | 0–5 library rating; MP3 POPM, FLAC RATING and WAV IRAT writing through private copies | MP3/WAV/FLAC rating round trips, preserved audio/comments/vendor/ReplayGain, combined edits and rescan; Android decodes the rated FLAC fixture |
| 39: ReplayGain | Native streaming K-weighted absolute/relative-gated analysis at −18 LUFS with sample-peak cap; calculated values saved in library | Known PCM assertions; signed release analyzes all 14 QA tracks; headless backup preserves all calculated gains |
| 40: duplicate finder | Review matching tags and streamed, byte-confirmed identical files; hide library rows only | Signed release detects an identical QA copy and keeps its source; review screenshot |

## Native manual checks

- Scanned the emulator's existing `/sdcard/Music` QA collection: 14 tracks, real artwork and tagged album groups. Shared music files were not modified.
- Chose a backup folder with Android's system picker and persisted its grant. Forced job `8202` repeatedly. `scripts/verify-emulator-backups.py` confirms five complete valid backups.
- Imported an `.ewbackup` through the Android document picker, restarted, and confirmed a `restore-safety.ewbackup` was created.
- Tested startup recovery with a deliberately invalid **app-owned emulator database**. The damaged file was quarantined, and the last verified automatic backup restored the 14-track library.
- Added the Quick Settings tile and toggled playback both ways while the panel stayed open. Its Play/Pause label changed with playback state.
- Pinned both new widget sizes in Pixel Launcher. Confirmed title, artist, cover, controls and favourite data, including updates while playback was paused.
- Registered all three launcher shortcuts; launched Favourites, Shuffle all and Resume actions.

The signed release was clean-installed, restored from a file, updated in place and played on the emulator. Its signature verifies and the merged manifest has no INTERNET permission. The headless release worker preserved 14 calculated gains and two playlists.


Emulator screenshots, logs, backup samples and per-build verification output are generated local artifacts. `docs/testing/` and build output are excluded from Git; the reusable tests and QA scripts remain in source control.

## Deliberate limits and physical-device validation

- Physical headphones/Bluetooth routing, subjective gapless timing and audio quality, audio interruptions and long OEM sleep sessions require a real Android phone. An emulator cannot certify these. Gapless is disabled by default.
- Rating file writes support MP3 ID3v2.3/v2.4, FLAC and WAV. Other formats retain ratings in the library, and the editor explains this. Unsupported ID3 flags/versions fail safely rather than rewriting an uncertain tag.
- Calculated ReplayGain values are stored in the database and included in backups; embedded music tags are not changed by analysis. Playback prefers existing ReplayGain tags.
- Crossfeed and PCM-WAV EQ use temporary 24-bit lossless FLAC playback copies because the bundled libmpv has no suitable channel-conversion/crossfeed filter. EQ itself runs in mpv. Derived copies are limited to five files and 512 MB per file; analysis rejects durations above 24 hours. Crossfeed is intended for stereo headphone listening.
- Android may defer periodic jobs. Backups also run when the app is used after the weekly interval. After a new-phone restore, choose the backup folder again because Android's storage grants are device-specific.
- Backup encoding and import both enforce a 512 MB expanded-payload limit, so an oversized export fails before producing an unrestorable file.
- Backups contain application data and cached artwork, not the music collection. Music must be copied separately and the destination folders re-scanned to relink tracks.

## Reproduce on Windows / Android

```powershell
flutter analyze
flutter test --reporter expanded
```

For screenshots and screen-off coverage, start the emulator. In one terminal:

```powershell
Set-Content emulator-drive.log ''
./scripts/monitor-emulator-test.ps1 -Log emulator-drive.log
```

In another terminal:

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d emulator-5554 *> emulator-drive.log
```

The helper scripts refuse physical-device power manipulation. Build the release sequentially after the test process has finished:

```powershell
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Verify its signature and merged permissions with the Android SDK's `apksigner` and `aapt`; the release must contain no `android.permission.INTERNET`.

