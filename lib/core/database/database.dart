import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  IntColumn get durationMs => integer()();
  TextColumn get genre => text().nullable()();
  TextColumn get albumArtPath => text().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
  IntColumn get totalPlayCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayed => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
}

@DataClassName('PlaybackHistoryEntry')
class PlaybackHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer().references(Tracks, #id)();
  DateTimeColumn get playedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Measured listening time, one row per stretch of a track actually played.
///
/// Deliberately separate from [PlaybackHistory]: that table records *that* a
/// play happened, and every stat built on it multiplies those rows by the
/// track's full duration — a track skipped after ten seconds counts the same
/// as one heard to the end. This table counts the audio that really came out,
/// so the two never have to agree and the existing stats keep their meaning.
@DataClassName('ListeningSessionEntry')
class ListeningSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer().references(Tracks, #id)();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();
}

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A saved query rather than a track list — see
/// features/playlists/models/smart_playlist.dart for what [rulesJson] holds.
/// Stored as JSON so adding a rule type doesn't need a schema migration.
class SmartPlaylists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get rulesJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class PlaylistTracks extends Table {
  IntColumn get playlistId => integer().references(Playlists, #id)();
  IntColumn get trackId => integer().references(Tracks, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

// ---------------------------------------------------------------------------
// Value/query helper types
// ---------------------------------------------------------------------------

enum LibrarySort { title, artist, dateAdded, playCount }

/// Album/artist grouping row, aggregated straight from the tracks table —
/// there are no separate album/artist tables, so identity is the name text.
class AlbumSummary {
  const AlbumSummary({
    required this.album,
    required this.artist,
    required this.trackCount,
    required this.totalMs,
    this.albumArtPath,
  });

  final String album;

  /// Album artist, taken as the most common artist on the album.
  final String artist;
  final int trackCount;
  final int totalMs;
  final String? albumArtPath;
}

class ArtistSummary {
  const ArtistSummary({
    required this.artist,
    required this.trackCount,
    required this.albumCount,
    required this.totalMs,
    this.albumArtPath,
  });

  final String artist;
  final int trackCount;
  final int albumCount;
  final int totalMs;
  final String? albumArtPath;
}

/// One directory containing audio files, derived from track file paths.
class FolderSummary {
  const FolderSummary({
    required this.path,
    required this.name,
    required this.trackCount,
  });

  final String path;
  final String name;
  final int trackCount;
}

class TopTrackStat {
  const TopTrackStat({required this.track, required this.playCount});

  final Track track;
  final int playCount;
}

/// Measured listening time for one track, from [ListeningSessions].
class TrackListeningStat {
  const TrackListeningStat({required this.track, required this.listenedMs});

  final Track track;
  final int listenedMs;
}

/// One day's measured listening, for the year-in-review heatmap.
class DailyListening {
  const DailyListening({required this.day, required this.listenedMs});

  /// Local midnight of the day.
  final DateTime day;
  final int listenedMs;
}

class TopArtistStat {
  const TopArtistStat({
    required this.artist,
    required this.playCount,
    required this.totalMs,
  });

  final String artist;
  final int playCount;
  final int totalMs;
}

class PlaylistWithCount {
  const PlaylistWithCount({required this.playlist, required this.trackCount});

  final Playlist playlist;
  final int trackCount;
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

const String kDatabaseFileName = 'electrowave.db';

Future<File> databaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, kDatabaseFileName));
}

@DriftDatabase(
  tables: [
    Tracks,
    PlaybackHistory,
    ListeningSessions,
    Playlists,
    PlaylistTracks,
    SmartPlaylists,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tracks, tracks.isFavorite);
        await m.addColumn(tracks, tracks.trackNumber);
        await m.addColumn(tracks, tracks.discNumber);
        await m.addColumn(tracks, tracks.year);
      }
      if (from < 3) {
        // Measured listening time starts accumulating from the upgrade;
        // there is nothing in the old data to backfill it from.
        await m.createTable(listeningSessions);
      }
      if (from < 4) {
        await m.createTable(smartPlaylists);
      }
    },
  );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final file = await databaseFile();
      return NativeDatabase.createInBackground(file);
    });
  }

  // -------------------------------------------------------------------------
  // Library
  // -------------------------------------------------------------------------

  Stream<List<Track>> watchLibrary({
    String search = '',
    LibrarySort sort = LibrarySort.title,
  }) {
    final query = select(tracks)..where((t) => t.isDeleted.equals(false));

    if (search.trim().isNotEmpty) {
      final needle = '%${search.trim()}%';
      query.where(
        (t) =>
            t.title.like(needle) | t.artist.like(needle) | t.album.like(needle),
      );
    }

    switch (sort) {
      case LibrarySort.title:
        query.orderBy([
          (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
        ]);
      case LibrarySort.artist:
        query.orderBy([
          (t) => OrderingTerm.asc(t.artist.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
        ]);
      case LibrarySort.dateAdded:
        query.orderBy([(t) => OrderingTerm.desc(t.dateAdded)]);
      case LibrarySort.playCount:
        query.orderBy([
          (t) => OrderingTerm.desc(t.totalPlayCount),
          (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
        ]);
    }

    return query.watch();
  }

  Future<Track?> trackById(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Live row for one track, so screens holding a Track snapshot (the player
  /// state, for instance) still reflect edits to favorites and tags.
  Stream<Track?> watchTrackById(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<List<Track>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<Track?> trackByPath(String path) =>
      (select(tracks)..where((t) => t.filePath.equals(path))).getSingleOrNull();

  /// Insert a scanned track, or revive/update the row if the path is already
  /// known (including soft-deleted rows, so play history is preserved).
  Future<int> upsertScannedTrack(TracksCompanion entry) async {
    final existing = await trackByPath(entry.filePath.value);
    if (existing == null) {
      return into(tracks).insert(entry);
    }
    await (update(tracks)..where((t) => t.id.equals(existing.id))).write(
      TracksCompanion(
        title: entry.title,
        artist: entry.artist,
        album: entry.album,
        durationMs: entry.durationMs,
        genre: entry.genre,
        albumArtPath: entry.albumArtPath,
        isDeleted: const Value(false),
      ),
    );
    return existing.id;
  }

  /// Backfill duration for formats where tag reading couldn't provide one
  /// (e.g. some wav/ogg files) once the player knows the real length.
  Future<void> updateTrackDurationIfMissing(int trackId, int durationMs) =>
      (update(tracks)
            ..where((t) => t.id.equals(trackId) & t.durationMs.equals(0)))
          .write(TracksCompanion(durationMs: Value(durationMs)));

  Future<void> softDeleteTrack(int trackId) =>
      (update(tracks)..where((t) => t.id.equals(trackId))).write(
        const TracksCompanion(isDeleted: Value(true)),
      );

  /// Edit tags in the library. Only non-absent fields are written, so callers
  /// can update a single field without clobbering the rest.
  Future<void> updateTrackTags(
    int trackId, {
    Value<String> title = const Value.absent(),
    Value<String> artist = const Value.absent(),
    Value<String> album = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    Value<int?> year = const Value.absent(),
  }) {
    return (update(tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Favorites
  // -------------------------------------------------------------------------

  Future<void> setFavorite(int trackId, bool favorite) =>
      (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion(isFavorite: Value(favorite)),
      );

  Stream<List<Track>> watchFavorites() {
    final query = select(tracks)
      ..where((t) => t.isDeleted.equals(false) & t.isFavorite.equals(true))
      ..orderBy([
        (t) => OrderingTerm.asc(t.artist.collate(Collate.noCase)),
        (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
        (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
      ]);
    return query.watch();
  }

  // -------------------------------------------------------------------------
  // Smart lists
  // -------------------------------------------------------------------------

  Stream<List<Track>> watchRecentlyAdded({int limit = 100}) {
    final query = select(tracks)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])
      ..limit(limit);
    return query.watch();
  }

  Stream<List<Track>> watchRecentlyPlayed({int limit = 100}) {
    final query = select(tracks)
      ..where((t) => t.isDeleted.equals(false) & t.lastPlayed.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.lastPlayed)])
      ..limit(limit);
    return query.watch();
  }

  Stream<List<Track>> watchMostPlayed({int limit = 100}) {
    final query = select(tracks)
      ..where(
        (t) =>
            t.isDeleted.equals(false) & t.totalPlayCount.isBiggerThanValue(0),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.totalPlayCount),
        (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
      ])
      ..limit(limit);
    return query.watch();
  }

  // -------------------------------------------------------------------------
  // Albums / artists
  // -------------------------------------------------------------------------

  /// Albums are grouped by album name only. Grouping by (album, artist) would
  /// split compilations and albums with featured guests into one row per
  /// artist, so the artist shown is the single artist when the album has one
  /// and 'Various artists' otherwise.
  Stream<List<AlbumSummary>> watchAlbums({String search = ''}) {
    final count = tracks.id.count();
    final totalMs = tracks.durationMs.sum();
    final art = tracks.albumArtPath.max();
    final anyArtist = tracks.artist.min();
    final artistCount = tracks.artist.count(distinct: true);

    final query = selectOnly(tracks)
      ..addColumns([tracks.album, count, totalMs, art, anyArtist, artistCount])
      ..where(tracks.isDeleted.equals(false))
      ..groupBy([tracks.album])
      ..orderBy([OrderingTerm.asc(tracks.album.collate(Collate.noCase))]);

    if (search.trim().isNotEmpty) {
      final needle = '%${search.trim()}%';
      query.where(tracks.album.like(needle) | tracks.artist.like(needle));
    }

    return query.map((row) {
      final distinctArtists = row.read(artistCount) ?? 0;
      return AlbumSummary(
        album: row.read(tracks.album) ?? '',
        artist: distinctArtists > 1
            ? 'Various artists'
            : (row.read(anyArtist) ?? ''),
        trackCount: row.read(count) ?? 0,
        totalMs: row.read(totalMs) ?? 0,
        albumArtPath: row.read(art),
      );
    }).watch();
  }

  Stream<List<ArtistSummary>> watchArtists({String search = ''}) {
    final count = tracks.id.count();
    final albumCount = tracks.album.count(distinct: true);
    final totalMs = tracks.durationMs.sum();
    final art = tracks.albumArtPath.max();

    final query = selectOnly(tracks)
      ..addColumns([tracks.artist, count, albumCount, totalMs, art])
      ..where(tracks.isDeleted.equals(false))
      ..groupBy([tracks.artist])
      ..orderBy([OrderingTerm.asc(tracks.artist.collate(Collate.noCase))]);

    if (search.trim().isNotEmpty) {
      query.where(tracks.artist.like('%${search.trim()}%'));
    }

    return query
        .map(
          (row) => ArtistSummary(
            artist: row.read(tracks.artist) ?? '',
            trackCount: row.read(count) ?? 0,
            albumCount: row.read(albumCount) ?? 0,
            totalMs: row.read(totalMs) ?? 0,
            albumArtPath: row.read(art),
          ),
        )
        .watch();
  }

  /// Album running order: disc, then track number, falling back to title for
  /// files whose tags carry no numbering.
  Stream<List<Track>> watchAlbumTracks(String album) {
    final query = select(tracks)
      ..where((t) => t.isDeleted.equals(false) & t.album.equals(album))
      ..orderBy([
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
      ]);
    return query.watch();
  }

  Stream<List<Track>> watchArtistTracks(String artist) {
    final query = select(tracks)
      ..where((t) => t.isDeleted.equals(false) & t.artist.equals(artist))
      ..orderBy([
        (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
        (t) => OrderingTerm.asc(t.discNumber),
        (t) => OrderingTerm.asc(t.trackNumber),
        (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
      ]);
    return query.watch();
  }

  Stream<List<AlbumSummary>> watchArtistAlbums(String artist) {
    final count = tracks.id.count();
    final totalMs = tracks.durationMs.sum();
    final art = tracks.albumArtPath.max();

    final query = selectOnly(tracks)
      ..addColumns([tracks.album, count, totalMs, art])
      ..where(tracks.isDeleted.equals(false) & tracks.artist.equals(artist))
      ..groupBy([tracks.album])
      ..orderBy([OrderingTerm.asc(tracks.album.collate(Collate.noCase))]);

    return query
        .map(
          (row) => AlbumSummary(
            album: row.read(tracks.album) ?? '',
            artist: artist,
            trackCount: row.read(count) ?? 0,
            totalMs: row.read(totalMs) ?? 0,
            albumArtPath: row.read(art),
          ),
        )
        .watch();
  }

  // -------------------------------------------------------------------------
  // Folders
  // -------------------------------------------------------------------------

  /// Grouped in Dart rather than SQL: SQLite has no dirname, and doing it here
  /// handles both path separators consistently.
  Stream<List<FolderSummary>> watchFolders() {
    final query = select(tracks)..where((t) => t.isDeleted.equals(false));
    return query.watch().map((rows) {
      final counts = <String, int>{};
      for (final row in rows) {
        final dir = p.dirname(row.filePath);
        counts[dir] = (counts[dir] ?? 0) + 1;
      }
      final folders = [
        for (final entry in counts.entries)
          FolderSummary(
            path: entry.key,
            name: p.basename(entry.key),
            trackCount: entry.value,
          ),
      ];
      folders.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      return folders;
    });
  }

  Stream<List<Track>> watchFolderTracks(String folderPath) {
    final query = select(tracks)..where((t) => t.isDeleted.equals(false));
    return query.watch().map((rows) {
      final inFolder = [
        for (final row in rows)
          if (p.dirname(row.filePath) == folderPath) row,
      ];
      inFolder.sort((a, b) {
        final disc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
        if (disc != 0) return disc;
        final track = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        if (track != 0) return track;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      return inFolder;
    });
  }

  // -------------------------------------------------------------------------
  // Trash (soft-deleted tracks)
  // -------------------------------------------------------------------------

  Stream<List<Track>> watchDeletedTracks() {
    final query = select(tracks)
      ..where((t) => t.isDeleted.equals(true))
      ..orderBy([(t) => OrderingTerm.asc(t.title.collate(Collate.noCase))]);
    return query.watch();
  }

  Future<void> restoreTrack(int trackId) =>
      (update(tracks)..where((t) => t.id.equals(trackId))).write(
        const TracksCompanion(isDeleted: Value(false)),
      );

  /// Permanently drop a library row and everything referencing it. Does not
  /// touch the audio file on disk.
  Future<void> purgeTrack(int trackId) async {
    await transaction(() async {
      await (delete(
        playlistTracks,
      )..where((pt) => pt.trackId.equals(trackId))).go();
      await (delete(
        playbackHistory,
      )..where((h) => h.trackId.equals(trackId))).go();
      await (delete(
        listeningSessions,
      )..where((s) => s.trackId.equals(trackId))).go();
      await (delete(tracks)..where((t) => t.id.equals(trackId))).go();
    });
  }

  Future<int> emptyTrash() async {
    final deleted = await (select(
      tracks,
    )..where((t) => t.isDeleted.equals(true))).get();
    for (final track in deleted) {
      await purgeTrack(track.id);
    }
    return deleted.length;
  }

  // -------------------------------------------------------------------------
  // Play tracking
  // -------------------------------------------------------------------------

  Future<void> recordPlay(int trackId) async {
    await transaction(() async {
      await into(
        playbackHistory,
      ).insert(PlaybackHistoryCompanion(trackId: Value(trackId)));
      final countExpr = tracks.totalPlayCount + const Constant(1);
      await (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion.custom(
          totalPlayCount: countExpr,
          lastPlayed: currentDateAndTime,
        ),
      );
    });
  }

  Future<void> clearPlayHistory() async {
    await transaction(() async {
      await delete(playbackHistory).go();
      await delete(listeningSessions).go();
      await update(tracks).write(
        const TracksCompanion(
          totalPlayCount: Value(0),
          lastPlayed: Value(null),
        ),
      );
    });
  }

  /// Opens a row for the stretch of [trackId] about to be played and returns
  /// its id; the caller tops up [saveListenedMs] as audio actually comes out.
  Future<int> startListeningSession(int trackId) => into(
    listeningSessions,
  ).insert(ListeningSessionsCompanion(trackId: Value(trackId)));

  /// Absolute value, not a delta — the caller owns the running total, so a
  /// dropped write costs precision rather than corrupting the count.
  Future<void> saveListenedMs(int sessionId, int listenedMs) =>
      (update(listeningSessions)..where((s) => s.id.equals(sessionId))).write(
        ListeningSessionsCompanion(listenedMs: Value(listenedMs)),
      );

  // -------------------------------------------------------------------------
  // Stats
  // -------------------------------------------------------------------------

  Expression<bool> _playedInRange(DateTime? from, DateTime? to) {
    Expression<bool> expr = const Constant(true);
    if (from != null) {
      expr = expr & playbackHistory.playedAt.isBiggerOrEqualValue(from);
    }
    if (to != null) {
      expr = expr & playbackHistory.playedAt.isSmallerThanValue(to);
    }
    return expr;
  }

  Stream<int> watchTotalListeningMs({DateTime? from, DateTime? to}) {
    final total = tracks.durationMs.sum();
    final query = selectOnly(playbackHistory)
      ..addColumns([total])
      ..join([innerJoin(tracks, tracks.id.equalsExp(playbackHistory.trackId))])
      ..where(_playedInRange(from, to));
    return query.map((row) => row.read(total) ?? 0).watchSingle();
  }

  Stream<List<TopTrackStat>> watchTopTracks({
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) {
    final plays = playbackHistory.id.count();
    final query =
        select(tracks).join([
            innerJoin(
              playbackHistory,
              playbackHistory.trackId.equalsExp(tracks.id),
              useColumns: false,
            ),
          ])
          ..addColumns([plays])
          ..where(_playedInRange(from, to))
          ..groupBy([tracks.id])
          ..orderBy([OrderingTerm.desc(plays)])
          ..limit(limit);
    return query
        .map(
          (row) => TopTrackStat(
            track: row.readTable(tracks),
            playCount: row.read(plays) ?? 0,
          ),
        )
        .watch();
  }

  Expression<bool> _listenedInRange(DateTime? from, DateTime? to) {
    Expression<bool> expr = const Constant(true);
    if (from != null) {
      expr = expr & listeningSessions.startedAt.isBiggerOrEqualValue(from);
    }
    if (to != null) {
      expr = expr & listeningSessions.startedAt.isSmallerThanValue(to);
    }
    return expr;
  }

  /// Tracks by measured listening time. Unlike [watchTopTracks] this counts
  /// the audio that actually played, so a track left on repeat outranks one
  /// that was started and skipped many times.
  Stream<List<TrackListeningStat>> watchTracksByListeningTime({
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) {
    final listened = listeningSessions.listenedMs.sum();
    final query =
        select(tracks).join([
            innerJoin(
              listeningSessions,
              listeningSessions.trackId.equalsExp(tracks.id),
              useColumns: false,
            ),
          ])
          ..addColumns([listened])
          ..where(_listenedInRange(from, to))
          ..groupBy([tracks.id])
          ..orderBy([OrderingTerm.desc(listened)])
          ..limit(limit);
    return query
        .map(
          (row) => TrackListeningStat(
            track: row.readTable(tracks),
            listenedMs: row.read(listened) ?? 0,
          ),
        )
        .watch();
  }

  /// Measured counterpart to [watchTotalListeningMs], which estimates from
  /// play counts instead.
  Stream<int> watchTotalListenedMs({DateTime? from, DateTime? to}) {
    final total = listeningSessions.listenedMs.sum();
    final query = selectOnly(listeningSessions)
      ..addColumns([total])
      ..where(_listenedInRange(from, to));
    return query.map((row) => row.read(total) ?? 0).watchSingle();
  }

  /// Listening per calendar day, in the device's local time.
  ///
  /// Grouped in SQL rather than in Dart: a year of sessions is thousands of
  /// rows and only ~365 of them survive the grouping. Drift stores DateTime as
  /// a unix timestamp, hence the `unixepoch` modifier; `localtime` is what
  /// makes a late-night listen land on the day the listener would call it.
  Stream<List<DailyListening>> watchDailyListening({
    required DateTime from,
    required DateTime to,
  }) {
    return customSelect(
      "SELECT date(started_at, 'unixepoch', 'localtime') AS day, "
      'SUM(listened_ms) AS ms FROM listening_sessions '
      'WHERE started_at >= ? AND started_at < ? GROUP BY day',
      variables: [
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {listeningSessions},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          if (DateTime.tryParse(row.read<String>('day')) case final day?)
            DailyListening(day: day, listenedMs: row.read<int?>('ms') ?? 0),
      ],
    );
  }

  /// How many distinct tracks were played in the window.
  Stream<int> watchDistinctTracksPlayed({DateTime? from, DateTime? to}) {
    final distinct = playbackHistory.trackId.count(distinct: true);
    final query = selectOnly(playbackHistory)
      ..addColumns([distinct])
      ..where(_playedInRange(from, to));
    return query.map((row) => row.read(distinct) ?? 0).watchSingle();
  }

  Stream<List<TopArtistStat>> watchTopArtists({
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) {
    final plays = playbackHistory.id.count();
    final totalMs = tracks.durationMs.sum();
    final query = selectOnly(playbackHistory)
      ..addColumns([tracks.artist, plays, totalMs])
      ..join([innerJoin(tracks, tracks.id.equalsExp(playbackHistory.trackId))])
      ..where(_playedInRange(from, to))
      ..groupBy([tracks.artist])
      ..orderBy([OrderingTerm.desc(plays)])
      ..limit(limit);
    return query
        .map(
          (row) => TopArtistStat(
            artist: row.read(tracks.artist) ?? '',
            playCount: row.read(plays) ?? 0,
            totalMs: row.read(totalMs) ?? 0,
          ),
        )
        .watch();
  }

  // -------------------------------------------------------------------------
  // Playlists
  // -------------------------------------------------------------------------

  Stream<List<PlaylistWithCount>> watchPlaylists() {
    final count = playlistTracks.trackId.count();
    final query =
        select(playlists).join([
            leftOuterJoin(
              playlistTracks,
              playlistTracks.playlistId.equalsExp(playlists.id),
            ),
          ])
          ..addColumns([count])
          ..groupBy([playlists.id])
          ..orderBy([OrderingTerm.asc(playlists.createdAt)]);
    return query
        .map(
          (row) => PlaylistWithCount(
            playlist: row.readTable(playlists),
            trackCount: row.read(count) ?? 0,
          ),
        )
        .watch();
  }

  Stream<Playlist?> watchPlaylist(int id) =>
      (select(playlists)..where((pl) => pl.id.equals(id))).watchSingleOrNull();

  Future<int> createPlaylist(String name) =>
      into(playlists).insert(PlaylistsCompanion(name: Value(name)));

  Future<void> renamePlaylist(int id, String name) =>
      (update(playlists)..where((pl) => pl.id.equals(id))).write(
        PlaylistsCompanion(name: Value(name)),
      );

  Future<void> deletePlaylist(int id) async {
    await transaction(() async {
      await (delete(
        playlistTracks,
      )..where((pt) => pt.playlistId.equals(id))).go();
      await (delete(playlists)..where((pl) => pl.id.equals(id))).go();
    });
  }

  Stream<List<Track>> watchPlaylistTracks(int playlistId) {
    final query =
        select(playlistTracks).join([
            innerJoin(tracks, tracks.id.equalsExp(playlistTracks.trackId)),
          ])
          ..where(
            playlistTracks.playlistId.equals(playlistId) &
                tracks.isDeleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(playlistTracks.position)]);
    return query.map((row) => row.readTable(tracks)).watch();
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    await transaction(() async {
      final maxPos = playlistTracks.position.max();
      final query = selectOnly(playlistTracks)
        ..addColumns([maxPos])
        ..where(playlistTracks.playlistId.equals(playlistId));
      final current = await query.map((row) => row.read(maxPos)).getSingle();
      await into(playlistTracks).insert(
        PlaylistTracksCompanion(
          playlistId: Value(playlistId),
          trackId: Value(trackId),
          position: Value((current ?? -1) + 1),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await (delete(playlistTracks)..where(
          (pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId),
        ))
        .go();
    await _normalizePositions(playlistId);
  }

  /// Persist a full reorder: [orderedTrackIds] is the new order.
  Future<void> reorderPlaylist(int playlistId, List<int> orderedTrackIds) {
    return transaction(() async {
      for (var i = 0; i < orderedTrackIds.length; i++) {
        await (update(playlistTracks)..where(
              (pt) =>
                  pt.playlistId.equals(playlistId) &
                  pt.trackId.equals(orderedTrackIds[i]),
            ))
            .write(PlaylistTracksCompanion(position: Value(i)));
      }
    });
  }

  Future<void> _normalizePositions(int playlistId) async {
    final rows =
        await (select(playlistTracks)
              ..where((pt) => pt.playlistId.equals(playlistId))
              ..orderBy([(pt) => OrderingTerm.asc(pt.position)]))
            .get();
    await transaction(() async {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].position != i) {
          await (update(playlistTracks)..where(
                (pt) =>
                    pt.playlistId.equals(playlistId) &
                    pt.trackId.equals(rows[i].trackId),
              ))
              .write(PlaylistTracksCompanion(position: Value(i)));
        }
      }
    });
  }

  // -------------------------------------------------------------------------
  // Smart playlists
  // -------------------------------------------------------------------------
  //
  // Only storage lives here. Turning the stored rules into a query needs the
  // rule model, so that part sits with the feature:
  // features/playlists/services/smart_playlist_query.dart.

  Stream<List<SmartPlaylist>> watchSmartPlaylists() {
    final query = select(smartPlaylists)
      ..orderBy([(sp) => OrderingTerm.asc(sp.createdAt)]);
    return query.watch();
  }

  Stream<SmartPlaylist?> watchSmartPlaylist(int id) => (select(
    smartPlaylists,
  )..where((sp) => sp.id.equals(id))).watchSingleOrNull();

  Future<int> createSmartPlaylist(String name, String rulesJson) =>
      into(smartPlaylists).insert(
        SmartPlaylistsCompanion(name: Value(name), rulesJson: Value(rulesJson)),
      );

  Future<void> updateSmartPlaylist(int id, String name, String rulesJson) =>
      (update(smartPlaylists)..where((sp) => sp.id.equals(id))).write(
        SmartPlaylistsCompanion(name: Value(name), rulesJson: Value(rulesJson)),
      );

  Future<void> deleteSmartPlaylist(int id) =>
      (delete(smartPlaylists)..where((sp) => sp.id.equals(id))).go();

  // -------------------------------------------------------------------------
  // Backup
  // -------------------------------------------------------------------------

  /// Write a consistent snapshot of the database to [targetPath] while the
  /// database stays open (VACUUM INTO gives a clean, compacted copy).
  Future<void> exportTo(String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await customStatement('VACUUM INTO ?', [targetPath]);
  }
}
