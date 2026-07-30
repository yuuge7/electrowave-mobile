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
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
  IntColumn get totalPlayCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayed => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

@DataClassName('PlaybackHistoryEntry')
class PlaybackHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer().references(Tracks, #id)();
  DateTimeColumn get playedAt => dateTime().withDefault(currentDateAndTime)();
}

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
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

class TopTrackStat {
  const TopTrackStat({required this.track, required this.playCount});

  final Track track;
  final int playCount;
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

@DriftDatabase(tables: [Tracks, PlaybackHistory, Playlists, PlaylistTracks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

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
            t.title.like(needle) |
            t.artist.like(needle) |
            t.album.like(needle),
      );
    }

    switch (sort) {
      case LibrarySort.title:
        query.orderBy([(t) => OrderingTerm.asc(t.title.collate(Collate.noCase))]);
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

  Future<List<Track>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows =
        await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  Future<Track?> trackByPath(String path) =>
      (select(tracks)..where((t) => t.filePath.equals(path)))
          .getSingleOrNull();

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
      (update(tracks)..where((t) => t.id.equals(trackId)))
          .write(const TracksCompanion(isDeleted: Value(true)));

  // -------------------------------------------------------------------------
  // Play tracking
  // -------------------------------------------------------------------------

  Future<void> recordPlay(int trackId) async {
    await transaction(() async {
      await into(playbackHistory)
          .insert(PlaybackHistoryCompanion(trackId: Value(trackId)));
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
      await update(tracks).write(const TracksCompanion(
        totalPlayCount: Value(0),
        lastPlayed: Value(null),
      ));
    });
  }

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
      ..join([
        innerJoin(tracks, tracks.id.equalsExp(playbackHistory.trackId)),
      ])
      ..where(_playedInRange(from, to));
    return query.map((row) => row.read(total) ?? 0).watchSingle();
  }

  Stream<List<TopTrackStat>> watchTopTracks({
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) {
    final plays = playbackHistory.id.count();
    final query = select(tracks).join([
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
        .map((row) => TopTrackStat(
              track: row.readTable(tracks),
              playCount: row.read(plays) ?? 0,
            ))
        .watch();
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
      ..join([
        innerJoin(tracks, tracks.id.equalsExp(playbackHistory.trackId)),
      ])
      ..where(_playedInRange(from, to))
      ..groupBy([tracks.artist])
      ..orderBy([OrderingTerm.desc(plays)])
      ..limit(limit);
    return query
        .map((row) => TopArtistStat(
              artist: row.read(tracks.artist) ?? '',
              playCount: row.read(plays) ?? 0,
              totalMs: row.read(totalMs) ?? 0,
            ))
        .watch();
  }

  // -------------------------------------------------------------------------
  // Playlists
  // -------------------------------------------------------------------------

  Stream<List<PlaylistWithCount>> watchPlaylists() {
    final count = playlistTracks.trackId.count();
    final query = select(playlists).join([
      leftOuterJoin(
        playlistTracks,
        playlistTracks.playlistId.equalsExp(playlists.id),
      ),
    ])
      ..addColumns([count])
      ..groupBy([playlists.id])
      ..orderBy([OrderingTerm.asc(playlists.createdAt)]);
    return query
        .map((row) => PlaylistWithCount(
              playlist: row.readTable(playlists),
              trackCount: row.read(count) ?? 0,
            ))
        .watch();
  }

  Stream<Playlist?> watchPlaylist(int id) =>
      (select(playlists)..where((pl) => pl.id.equals(id)))
          .watchSingleOrNull();

  Future<int> createPlaylist(String name) =>
      into(playlists).insert(PlaylistsCompanion(name: Value(name)));

  Future<void> renamePlaylist(int id, String name) =>
      (update(playlists)..where((pl) => pl.id.equals(id)))
          .write(PlaylistsCompanion(name: Value(name)));

  Future<void> deletePlaylist(int id) async {
    await transaction(() async {
      await (delete(playlistTracks)..where((pt) => pt.playlistId.equals(id)))
          .go();
      await (delete(playlists)..where((pl) => pl.id.equals(id))).go();
    });
  }

  Stream<List<Track>> watchPlaylistTracks(int playlistId) {
    final query = select(playlistTracks).join([
      innerJoin(tracks, tracks.id.equalsExp(playlistTracks.trackId)),
    ])
      ..where(playlistTracks.playlistId.equals(playlistId) &
          tracks.isDeleted.equals(false))
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
    await (delete(playlistTracks)
          ..where((pt) =>
              pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
        .go();
    await _normalizePositions(playlistId);
  }

  /// Persist a full reorder: [orderedTrackIds] is the new order.
  Future<void> reorderPlaylist(int playlistId, List<int> orderedTrackIds) {
    return transaction(() async {
      for (var i = 0; i < orderedTrackIds.length; i++) {
        await (update(playlistTracks)
              ..where((pt) =>
                  pt.playlistId.equals(playlistId) &
                  pt.trackId.equals(orderedTrackIds[i])))
            .write(PlaylistTracksCompanion(position: Value(i)));
      }
    });
  }

  Future<void> _normalizePositions(int playlistId) async {
    final rows = await (select(playlistTracks)
          ..where((pt) => pt.playlistId.equals(playlistId))
          ..orderBy([(pt) => OrderingTerm.asc(pt.position)]))
        .get();
    await transaction(() async {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].position != i) {
          await (update(playlistTracks)
                ..where((pt) =>
                    pt.playlistId.equals(playlistId) &
                    pt.trackId.equals(rows[i].trackId)))
              .write(PlaylistTracksCompanion(position: Value(i)));
        }
      }
    });
  }

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
