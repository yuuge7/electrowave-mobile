import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Title + artist is what makes two rows the same song. These are the cases
/// where a path alone got it wrong: a renamed file, a second copy, and the
/// duplicates an earlier rename already left behind.
void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('same_song');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  String pathOf(String name) => p.join(dir.path, name);

  /// Real files, because whether the old path still exists decides which path
  /// a row ends up with.
  Future<String> onDisk(String name) async {
    final file = File(pathOf(name));
    await file.create();
    return file.path;
  }

  TracksCompanion entry(
    String path, {
    String title = 'Night Drive',
    String artist = 'Echo Unit',
  }) {
    return TracksCompanion.insert(
      filePath: path,
      title: title,
      artist: artist,
      album: 'Test Kit',
      durationMs: 20000,
    );
  }

  Future<int> scan(
    String path, {
    String title = 'Night Drive',
    String artist = 'Echo Unit',
  }) => db.upsertScannedTrack(entry(path, title: title, artist: artist));

  Future<List<Track>> library() => db.watchLibrary().first;

  group('scanning', () {
    test('a renamed file keeps its row and everything on it', () async {
      final before = await onDisk('Night Drive (Official Video) [yt].mp3');
      final id = await scan(before);
      await db.recordPlay(id);
      await db.setFavorite(id, true);
      final playlist = await db.createPlaylist('Drives');
      await db.addTrackToPlaylist(playlist, id);

      final after = pathOf('Night Drive.mp3');
      await File(before).rename(after);
      final rescanned = await scan(after);

      final tracks = await library();
      expect(rescanned, id);
      expect(tracks, hasLength(1));
      expect(tracks.single.filePath, after);
      expect(tracks.single.totalPlayCount, 1);
      expect(tracks.single.isFavorite, isTrue);
      expect(await db.watchPlaylistTracks(playlist).first, hasLength(1));
    });

    test('a second copy next to the first is not added again', () async {
      final first = await onDisk('Night Drive (Official Video) [yt].mp3');
      final second = await onDisk('Night Drive.mp3');
      final id = await scan(first);

      expect(await scan(second), id);

      final tracks = await library();
      expect(tracks, hasLength(1));
      // The file it could already play stays the one it plays.
      expect(tracks.single.filePath, first);
    });

    test('matching ignores case', () async {
      final id = await scan(pathOf('gone.mp3'));

      final rescanned = await scan(
        await onDisk('night drive.mp3'),
        title: 'night drive',
        artist: 'ECHO UNIT',
      );

      expect(rescanned, id);
      expect(await library(), hasLength(1));
    });

    test('a different artist is a different song', () async {
      await scan(await onDisk('a.mp3'));
      await scan(await onDisk('b.mp3'), artist: 'Someone Else');

      expect(await library(), hasLength(2));
    });

    test('untagged files never match on title alone', () async {
      for (final name in ['a.mp3', 'b.mp3']) {
        await scan(await onDisk(name), title: 'Intro', artist: kUnknownArtist);
      }

      expect(await library(), hasLength(2));
    });

    // The state a rename left behind before rows were matched by song: the
    // old row with the history and no file, the new row with the file.
    test('a rescan folds in the duplicate an earlier rename left', () async {
      final stale = await db.into(db.tracks).insert(entry(pathOf('gone.mp3')));
      await db.recordPlay(stale);
      await db.recordPlay(stale);
      final playlist = await db.createPlaylist('Drives');
      await db.addTrackToPlaylist(playlist, stale);

      final live = await onDisk('Night Drive.mp3');
      final fresh = await db.into(db.tracks).insert(entry(live));
      await db.recordPlay(fresh);

      expect(await scan(live), fresh);

      final tracks = await library();
      expect(tracks, hasLength(1));
      expect(tracks.single.id, fresh);
      expect(tracks.single.filePath, live);
      expect(tracks.single.totalPlayCount, 3);
      expect(await db.watchPlayCount().first, 3);
      expect(
        (await db.watchPlaylistTracks(playlist).first).single.id,
        fresh,
      );
    });
  });

  group('retagging', () {
    test('into a song already in the library folds the two', () async {
      // Old entry: tagged in the app, file since renamed away.
      final old = await scan(pathOf('gone.mp3'));
      await db.recordPlay(old);
      final playlist = await db.createPlaylist('Drives');
      await db.addTrackToPlaylist(playlist, old);

      // The renamed file carries no artist, so it scans as a new song.
      final live = await onDisk('Night Drive.mp3');
      final renamed = await scan(live, artist: kUnknownArtist);
      await db.addTrackToPlaylist(playlist, renamed);
      expect(await library(), hasLength(2));

      await db.updateTrackTags(renamed, artist: const Value('Echo Unit'));

      final tracks = await library();
      expect(tracks, hasLength(1));
      expect(tracks.single.id, renamed);
      expect(tracks.single.filePath, live);
      expect(tracks.single.totalPlayCount, 1);
      // Both rows were on the playlist; the song is on it once.
      expect(await db.watchPlaylistTracks(playlist).first, hasLength(1));
    });

    test('a row whose file is gone takes the file of the one it absorbs', () async {
      final live = await onDisk('Night Drive.mp3');
      await scan(live);
      final old = await scan(pathOf('gone.mp3'), artist: 'Echo Unti');

      await db.updateTrackTags(old, artist: const Value('Echo Unit'));

      final tracks = await library();
      expect(tracks, hasLength(1));
      expect(tracks.single.id, old);
      expect(tracks.single.filePath, live);
    });
  });
}
