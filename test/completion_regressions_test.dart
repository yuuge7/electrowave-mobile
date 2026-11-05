import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/features/settings/services/backup_service.dart';
import 'package:electrowave_mobile/features/player/services/playback_persistence.dart';
import 'package:electrowave_mobile/features/player/providers/player_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('electrowave_regression_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> insert(String name, {String artist = 'Artist'}) => db
      .into(db.tracks)
      .insert(
        TracksCompanion.insert(
          filePath: '${dir.path}/$name.mp3',
          title: name,
          artist: artist,
          album: 'Album',
          durationMs: 3000,
        ),
      );

  test(
    '50,000-entry queue lookup preserves order and repeated tracks',
    () async {
      final a = await insert('A'), b = await insert('B');
      // Real queues can exceed SQLite's host-parameter limit. Most entries may
      // repeat; lookup must still return the original queue, in its exact order.
      final ids = List.generate(50000, (i) => i.isEven ? b : a);
      final tracks = await db.tracksByIds(ids);
      expect(tracks.map((t) => t.id), ids);
    },
  );

  test('folding duplicate rows keeps ratings, starts, skips and gain', () async {
    final keep = await insert('Song'), twin = await insert('Other');
    await db.customUpdate(
      'UPDATE tracks SET rating=2,start_count=3,skip_count=1 WHERE id=?',
      variables: [Variable.withInt(keep)],
      updates: {db.tracks},
    );
    await db.customUpdate(
      'UPDATE tracks SET rating=5,start_count=4,skip_count=2,replay_gain_db=-4.5 WHERE id=?',
      variables: [Variable.withInt(twin)],
      updates: {db.tracks},
    );
    await db.recordPlay(twin);
    final session = await db.startListeningSession(twin);
    await db.saveListenedMs(session, 1234);
    await db.updateTrackTags(keep, title: const Value('Other'));
    final track = (await db.trackById(keep))!;
    expect(track.startCount, 7);
    expect(track.skipCount, 3);
    expect(track.rating, 5);
    expect(track.replayGainDb, -4.5);
    expect(track.totalPlayCount, 1);
    expect(await db.watchTotalListenedMs().first, 1234);
    expect(await db.trackById(twin), isNull);
  });

  test('clearing history also resets starts and skips', () async {
    final id = await insert('Song');
    await db.recordPlay(id);
    await db.recordStart(id);
    await db.recordSkip(id);
    await db.clearPlayHistory();
    final track = (await db.trackById(id))!;
    expect(track.totalPlayCount, 0);
    expect(track.startCount, 0);
    expect(track.skipCount, 0);
    expect(track.lastPlayed, isNull);
  });

  test('a backup missing a required nullable column is rejected', () async {
    await insert('Keep');
    final file = File('${dir.path}/incomplete.db');
    await db.exportTo(file.path);
    final raw = sqlite3.open(file.path);
    raw.execute('ALTER TABLE tracks DROP COLUMN last_played');
    raw.close();
    expect(
      () => BackupService.validateDatabase(file.path),
      throwsFormatException,
    );
  });

  test('malformed queue lists are rejected eagerly', () {
    expect(
      PersistedPlayback.fromJson({
        'contextTrackIds': [1, 'bad'],
      }),
      isNull,
    );
    expect(
      PersistedPlayback.fromJson({
        'shuffleOrder': [null],
      }),
      isNull,
    );
  });

  test(
    'restore remaps shuffle and current index after removed tracks',
    () async {
      final a = await insert('A'), b = await insert('B'), c = await insert('C');
      await db.softDeleteTrack(b);
      final rows = await db.tracksByIds([a, b, c]);
      final saved = PersistedPlayback(
        currentTrackId: c,
        positionMs: 42,
        contextTrackIds: [a, b, c, 999],
        contextName: 'Library',
        manualQueueIds: [b, a],
        contextIndex: 2,
        shuffle: true,
        shuffleOrder: [2, 1, 3, 0],
        repeatIndex: 0,
        fromManualQueue: false,
      );
      final queue = PlayerQueueState.restored(
        saved,
        current: rows.last,
        contextTracks: rows,
        manualTracks: [rows[1], rows[0]],
      );
      expect(queue.context.map((t) => t.id), [a, c]);
      expect(queue.contextIndex, 1);
      expect(queue.shuffleOrder, [1, 0]);
      expect(queue.upcomingContext.map((t) => t.id), [a]);
      expect(queue.manualQueue.map((t) => t.id), [a]);
      final malformed = PersistedPlayback.fromJson({
        ...saved.toJson(),
        'shuffleOrder': [200, -1, 0, 0],
      })!;
      final recovered = PlayerQueueState.restored(
        malformed,
        current: rows.last,
        contextTracks: rows,
        manualTracks: [],
      );
      expect(recovered.shuffleOrder, [1, 0]);
      expect(recovered.upcomingContext.map((t) => t.id), [a]);
      final repeated = PersistedPlayback.fromJson({
        ...saved.toJson(),
        'contextTrackIds': [c, a, c],
        'contextIndex': 2,
        'shuffleOrder': [2, 1, 0],
      })!;
      final repeatedQueue = PlayerQueueState.restored(
        repeated,
        current: rows.last,
        contextTracks: rows,
        manualTracks: [],
      );
      expect(repeatedQueue.contextIndex, 2);
      expect(repeatedQueue.upcomingContext.map((t) => t.id), [a, c]);
    },
  );

  test('backup validates the contents of settings, queue and folder files', () {
    for (final entry in {
      'settings.json': {'playbackRate': 'broken'},
      'playback_state.json': {
        'manualQueueIds': [1, 'broken'],
      },
      'library.json': {
        'folders': ['/Music', 42],
      },
    }.entries) {
      final bytes = BackupBundle({
        'database': Uint8List(0),
        entry.key: Uint8List.fromList(utf8.encode(jsonEncode(entry.value))),
      }).encode();
      expect(() => BackupBundle.decode(bytes), throwsFormatException);
    }
  });

  test(
    'startup repairs missing search triggers and rebuilds missed rows',
    () async {
      await insert('Original');
      final file = File('${dir.path}/search.db');
      await db.exportTo(file.path);
      await db.close();
      final raw = sqlite3.open(file.path);
      raw.execute('DROP TRIGGER track_search_insert');
      raw.execute(
        "INSERT INTO tracks(file_path,title,artist,album,duration_ms) VALUES('/new','Recovered','Artist','Album',1000)",
      );
      raw.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect(
        (await db.watchLibrary(search: 'Recovered').first).single.title,
        'Recovered',
      );
      await insert('Subsequent');
      expect(
        (await db.watchLibrary(search: 'Subsequent').first).single.title,
        'Subsequent',
      );
    },
  );
}
