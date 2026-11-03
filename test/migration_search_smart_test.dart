import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/features/playlists/services/smart_playlist_query.dart';
import 'package:electrowave_mobile/features/playlists/models/smart_playlist.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('upgrades real v1-v5 schemas without losing plays or playlists', () async {
    final dir = await Directory.systemTemp.createTemp('electrowave_migration_');
    try {
      for (var version = 1; version <= 5; version++) {
        final file = File('${dir.path}/v$version.db');
        final db = AppDatabase.forTesting(NativeDatabase(file));
        final id = await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                filePath: '/music/test.mp3',
                title: 'Keep',
                artist: 'Artist',
                album: 'Album',
                durationMs: 1000,
              ),
            );
        await db.recordPlay(id);
        final playlist = await db.createPlaylist('Keep list');
        await db.addTrackToPlaylist(playlist, id);
        await db.close();
        final raw = sqlite3.open(file.path);
        // Strip new features to recreate each historical schema, including old table shapes.
        for (final trigger in ['insert', 'delete', 'update']) {
          raw.execute('DROP TRIGGER track_search_$trigger');
        }
        raw.execute('DROP TABLE track_search');
        for (final column in [
          'album_artist',
          'file_size',
          'file_modified_ms',
          'rating',
          'replay_gain_db',
          'skip_count',
          'start_count',
        ]) {
          raw.execute('ALTER TABLE tracks DROP COLUMN $column');
        }
        if (version < 5) {
          raw.execute('ALTER TABLE playlists DROP COLUMN pinned_at');
          raw.execute('ALTER TABLE smart_playlists DROP COLUMN pinned_at');
        }
        if (version < 4) raw.execute('DROP TABLE smart_playlists');
        if (version < 3) raw.execute('DROP TABLE listening_sessions');
        if (version < 2) {
          for (final column in [
            'is_favorite',
            'track_number',
            'disc_number',
            'year',
          ]) {
            raw.execute('ALTER TABLE tracks DROP COLUMN $column');
          }
        }
        raw.execute('PRAGMA user_version=$version');
        raw.close();
        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        final tracks = await upgraded.watchLibrary().first;
        expect(tracks.single.title, 'Keep');
        expect(tracks.single.totalPlayCount, 1);
        expect(
          (await upgraded.watchPlaylistTracks(playlist).first).single.id,
          id,
        );
        expect(
          (await upgraded.watchLibrary(search: 'Kee').first).single.id,
          id,
        );
        expect(tracks.single.rating, 0);
        await upgraded.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'indexed 10,500-song search, ordering and album artist grouping',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        await db.batch(
          (batch) => batch.insertAll(db.tracks, [
            for (var i = 0; i < 10500; i++)
              TracksCompanion.insert(
                filePath: '/music/$i.mp3',
                title: 'Song $i',
                artist: 'Artist ${i % 200}',
                album: 'Album ${i % 500}',
                durationMs: 180000,
                albumArtist: Value(i % 2 == 0 ? 'Compilation' : null),
              ),
          ]),
        );
        final watch = Stopwatch()..start();
        final matches = await db.watchLibrary(search: 'Song 10499').first;
        watch.stop();
        expect(matches.single.title, 'Song 10499');
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 10)),
          reason: 'Search must remain interactive',
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'smart rules cover all/any, measured time, null dates, sorting and caps',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final a = await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                filePath: '/a',
                title: 'Alpha',
                artist: 'Artist',
                album: 'Album',
                durationMs: 120000,
                genre: const Value('House'),
                isFavorite: const Value(true),
                year: const Value(2020),
              ),
            );
        final b = await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                filePath: '/b',
                title: 'Beta',
                artist: 'Other',
                album: 'Album',
                durationMs: 60000,
                genre: const Value('Rock'),
              ),
            );
        await db.recordPlay(a);
        final session = await db.startListeningSession(b);
        await db.saveListenedMs(session, 90000);
        Future<List<Track>> query(
          List<SmartRule> rules, {
          bool all = true,
          SmartSort sort = SmartSort.title,
          bool descending = false,
          int? limit,
        }) => watchSmartPlaylistTracks(
          db,
          SmartPlaylistDefinition(
            rules: rules,
            matchAll: all,
            sort: sort,
            descending: descending,
            limit: limit,
          ),
        ).first;
        expect(
          (await query([
            const SmartRule(
              field: SmartField.genre,
              operator: SmartOperator.equals,
              value: 'house',
            ),
            const SmartRule(
              field: SmartField.favorite,
              operator: SmartOperator.isTrue,
            ),
          ])).single.id,
          a,
        );
        expect(
          await query([
            const SmartRule(
              field: SmartField.favorite,
              operator: SmartOperator.isTrue,
            ),
            const SmartRule(
              field: SmartField.genre,
              operator: SmartOperator.equals,
              value: 'Rock',
            ),
          ], all: false),
          hasLength(2),
        );
        expect(
          (await query([
            const SmartRule(
              field: SmartField.listenedMinutes,
              operator: SmartOperator.greaterThan,
              value: '1',
            ),
          ])).single.id,
          b,
        );
        expect(
          (await query([
            const SmartRule(
              field: SmartField.lastPlayed,
              operator: SmartOperator.never,
            ),
          ])).single.id,
          b,
        );
        expect(
          (await query(
            [],
            sort: SmartSort.title,
            descending: true,
            limit: 1,
          )).single.id,
          b,
        );
        expect(
          (await query([
            const SmartRule(
              field: SmartField.year,
              operator: SmartOperator.greaterThan,
              value: '2010',
            ),
          ])).single.id,
          a,
        );
        expect(
          await query([
            const SmartRule(
              field: SmartField.playCount,
              operator: SmartOperator.greaterThan,
              value: 'bad',
            ),
          ]),
          hasLength(2),
        );
        await db.softDeleteTrack(a);
        expect(await query([]), hasLength(1));
      } finally {
        await db.close();
      }
    },
  );
}
