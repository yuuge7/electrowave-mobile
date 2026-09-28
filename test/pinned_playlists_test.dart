import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/core/database/database_provider.dart';
import 'package:electrowave_mobile/features/playlists/providers/playlist_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two playlist tables as they stood before pinning (schema 4).
const _playlistsV4 = '''
CREATE TABLE playlists (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
)''';

const _smartPlaylistsV4 = '''
CREATE TABLE smart_playlists (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  rules_json TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
)''';

/// Opens a database whose file claims [version], holding only [tables]. The
/// steps from 3 upward touch nothing else, so nothing else has to exist.
AppDatabase _openAt(int version, List<String> tables) {
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) {
        for (final sql in tables) {
          raw.execute(sql);
        }
        raw.execute('PRAGMA user_version = $version');
      },
    ),
  );
}

Future<void> _expectPinnable(AppDatabase db) async {
  final manual = await db.createPlaylist('Manual');
  final smart = await db.createSmartPlaylist('Smart', '{}');
  await db.setPlaylistPinned(manual, pinned: true);
  await db.setSmartPlaylistPinned(smart, pinned: true);

  expect((await db.watchPlaylist(manual).first)!.pinnedAt, isNotNull);
  expect((await db.watchSmartPlaylist(smart).first)!.pinnedAt, isNotNull);
}

void main() {
  group('migration to 5', () {
    test('adds the pin column to both tables from 4', () async {
      final db = _openAt(4, [_playlistsV4, _smartPlaylistsV4]);
      addTearDown(db.close);

      await _expectPinnable(db);
    });

    // From 3 the smart table is created by the step to 4, already carrying
    // the pin column — adding it again would fail with a duplicate column.
    test('does not add the pin column twice from 3', () async {
      final db = _openAt(3, [_playlistsV4]);
      addTearDown(db.close);

      await _expectPinnable(db);
    });
  });

  group('pinning', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<List<PinnedPlaylist>> settledPins() async {
      container.listen(pinnedPlaylistsProvider, (_, _) {});
      await container.read(playlistsProvider.future);
      await container.read(smartPlaylistsProvider.future);
      // Let both streams deliver the latest write before reading the merge.
      await pumpEventQueue();
      return container.read(pinnedPlaylistsProvider);
    }

    test('unpinning clears the stamp', () async {
      final id = await db.createPlaylist('Drives');
      await db.setPlaylistPinned(id, pinned: true);
      await db.setPlaylistPinned(id, pinned: false);

      expect((await db.watchPlaylist(id).first)!.pinnedAt, isNull);
    });

    test('merges both kinds in the order they were pinned', () async {
      final first = await db.createPlaylist('First');
      final second = await db.createSmartPlaylist('Second', '{}');
      final third = await db.createPlaylist('Third');
      await db.createPlaylist('Never pinned');

      // Stamps are stored to the second, so write them directly rather than
      // sleeping between pins.
      DateTime at(int minute) => DateTime(2026, 1, 1, 0, minute);
      await (db.update(db.playlists)..where((p) => p.id.equals(first))).write(
        PlaylistsCompanion(pinnedAt: Value(at(1))),
      );
      await (db.update(db.smartPlaylists)..where((p) => p.id.equals(second)))
          .write(SmartPlaylistsCompanion(pinnedAt: Value(at(2))));
      await (db.update(db.playlists)..where((p) => p.id.equals(third))).write(
        PlaylistsCompanion(pinnedAt: Value(at(3))),
      );

      final pins = await settledPins();

      expect(pins.map((p) => p.name), ['First', 'Second', 'Third']);
      expect(pins[1], isA<PinnedSmartPlaylist>());
      expect(pins[1].location, '/playlists/smart/$second');
      expect(pins[2].location, '/playlists/$third');
    });
  });
}
