# Electrowave — Ideas

**Goal:** a music player that feels finished, safe and premium — good enough for someone who
can buy anything — while staying 100% offline.

**Ground rules (never break these):**

- No accounts. No login. No cloud.
- Nothing leaves the phone. The release app has **no internet permission** — keep it that way.
- Moving data in or out = **files only** (export / import).

**How to read this file:** start at the top. Each section is more optional than the one before it.
Tick the box when an item is done.

---

## 1. Fix first — trust and safety

If any of these go wrong, someone loses their data. Nothing else matters until they are solid.

- [x] **Safety copy before import.** Import currently deletes the live database. Save a copy of it
      first, so a bad backup can be undone.
- [x] **Check the backup before accepting it.** Today any SQLite file passes. Check that it really
      is an Electrowave backup, that it is not damaged, and that it is not from a newer app version.
- [x] **Back up everything, not just the database.** Settings, EQ, theme, queue and library
      folders live outside the database, so a restore loses them. Put it all in one backup file.
- [x] **Restore on a new phone.** Music paths differ between phones, so restored tracks point to
      nothing. After a restore, match old tracks to new files (by path ending, then by tags) so
      history, playlists and stats carry over.
- [x] **Automatic backups.** Optional: pick a folder once, then the app saves a backup there
      every week and keeps the last 5.
- [x] **Remember library folders.** The "Re-scan" option forgets the folder after a restart, and
      only one folder is allowed. Save a list of folders and re-scan all of them.
- [x] **Local crash log.** Catch every error, write it to a small file on the phone, and add
      "Export crash log" in Settings. Nothing is sent anywhere — you share it by hand if you want.
- [x] **Database health check on startup.** If the database is damaged, offer to restore the last
      automatic backup instead of crashing.

---

## 2. Fast with big libraries

A serious collection is 10,000–50,000 songs. The app must stay smooth at that size.

- [x] **Fast re-scans.** Every scan re-reads every file. Remember each file's size and date and
      skip the ones that did not change. Turns minutes into seconds.
- [x] **Cancel a scan.** There is no way to stop a scan today. Add a cancel button, a progress
      bar, the file count and the current folder.
- [x] **Scan keeps going in the background** when you leave the Library tab.
- [x] **A–Z fast-scroll** rail on tracks, albums and artists.
- [x] **Faster search** with a proper search index, so typing stays instant on huge libraries.
- [x] **Test with 10,000+ songs** before calling any screen finished.

---

## 3. Everyday features people expect

- [x] **Select many songs at once** in the library (long-press) — then add to queue, add to
      playlist, edit tags or remove, all in one go.
- [x] **Sort direction** — ascending / descending toggle next to the sort menu, remembered.
- [x] **Queue: "Save as playlist"** and **"Clear queue."**
- [x] **Album artist support.** Group albums by the "album artist" tag, so compilations stop
      breaking apart. Fall back to today's behaviour when the tag is missing.
- [x] **Library summary** in Settings: song count, total hours, size on disk, formats.
- [x] **Browse by genre and by year/decade.** The data is already there.
- [x] **Playlist file import/export** (`.m3u` / `.m3u8`) so playlists work in other players too.
- [x] **Export stats** as CSV / JSON for people who want their own charts.

---

## 4. The premium feel

The small things that make an app feel expensive.

- [x] **Settings split into pages** (Library, Playback, Audio, Appearance, Backup, About) instead
      of one long list.
- [x] **About page** that says it out loud: version, licence, and "No internet. No account. No
      tracking."
- [x] **Private session** — a switch that stops recording plays and stats for a while.
- [x] **App shortcuts** (long-press the icon): Shuffle all, Resume, Favourites.
- [x] **Quick Settings tile** for play / pause.
- [x] **More widget sizes** — a big 2×2 with cover art, and a 4×2 with progress and favourite.
- [x] **Themed (monochrome) app icon** for Android 13+.
- [x] **Better EQ** — 10 bands, save your own presets, separate profiles for headphones,
      Bluetooth and speaker.
- [x] **Mono audio** switch (helps people with hearing loss in one ear) and **crossfeed** for
      headphones.
- [x] **Stats extras** — skip rate per song, "what hour do I listen most", genre breakdown,
      "forgotten favourites" (loved or ex-very played songs not played in 6 months).

---

## 5. Professional build process

What keeps the app from breaking as it grows.

- [x] **Tests run before every release.** CI builds and publishes on every push to `main`, but
      never runs `flutter analyze` or `flutter test`. Add both as a gate.
- [x] **Database upgrade tests** — open an old-version database and check it upgrades cleanly.
- [x] **Tests for smart playlist rules** — the most complex logic, still not tested.

---

## 6. Big projects (later, each one needs testing on a real phone)

- [x] **Gapless playback** — no silence between tracks. Only the careful "current + next track"
      version (see "Do NOT" below).
- [x] **Waveform seek bar** — a real waveform instead of a flat line.
- [x] **Star ratings (0–5)**, saved into the file's tags.
- [x] **ReplayGain calculation** for files that don't have it in their tags.
- [x] **Duplicate finder** with a review screen.

---

**Android implementation:** all 40 items have implementations. Revalidated 5 November 2026 with 251 unit/widget tests, Android emulator checks and signed-release UI checks. The physical-phone checks for section 6 remain pending; emulator checks do not certify real headphones, Bluetooth or OEM sleep behaviour.

## Do NOT do

Things we already know are wrong for this app.

### Against the product

- **No accounts, login or cloud sync.** Files only.
- **No internet permission.** It is what makes the "nothing leaves the phone" promise true.
- **No analytics, no crash-reporting services** (Firebase, Sentry, …). They send data out.
  Use the local crash log instead.
- **No Last.fm scrobbling, online lyrics, online cover art or "check for updates".** All need
  the internet.
- **No ads, in-app purchases, rating pop-ups or store-only features.** It is not on a store.
- **Never touch the user's music files without being asked.** Removing a song only hides it.
  Only the tag editor writes to files.

### Already tried or known to break things

- **Don't merge plays and listening time.** `PlaybackHistory` (a play happened) and
  `ListeningSessions` (time actually heard) measure different things on purpose.
- **Don't hand the whole queue to mpv for gapless.** Two things would control the queue and
  fight each other. Only the two-track version is allowed, and only after testing through screen
  -off and sleep.
- **Don't set `androidStopForegroundOnPause` to `true`.** Playback dies mid-queue when the phone
  sleeps.
- **Don't update the notification on every position tick.** Only on play, pause, seek and
  buffering.
- **Don't group albums by album + artist** (without an album-artist tag). It breaks compilations.
- **Don't use Android's built-in equalizer.** The player can't reach it; the EQ runs inside mpv.
- **Don't update `file_picker` to 11.x or change `android.builtInKotlin`.** The build breaks.
- **Don't decode album art at full size.** Large art fails to load; always pass a size limit.
- **Don't use `certutil` for the release keystore.** Use the PowerShell command in the README.
- **No loud fonts or gimmicky number styles.** The look comes from layout and structure, not
  from flashy type.
- **No new packages for things that are easy to write by hand** (like the colour-from-artwork
  code). Fewer packages = fewer surprises.
