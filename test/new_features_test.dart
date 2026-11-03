import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/core/database/database_provider.dart';
import 'package:electrowave_mobile/features/stats/views/listening_extras_screen.dart';
import 'package:electrowave_mobile/features/library/services/rating_tags.dart';
import 'package:electrowave_mobile/features/library/services/tag_writer.dart';
import 'package:electrowave_mobile/features/library/services/library_scanner.dart';
import 'package:electrowave_mobile/features/playlists/services/playlist_file_service.dart';

void main() {
  test(
    'listening extras split hour boundaries and exclude new favourites from forgotten tracks',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      try {
        final old = DateTime.now().subtract(const Duration(days: 240));
        final now = DateTime.now();
        final ids = <int>[];
        for (var i = 0; i < 3; i++) {
          ids.add(
            await db
                .into(db.tracks)
                .insert(
                  TracksCompanion.insert(
                    filePath: '/stats-$i',
                    title: 'Stats $i',
                    artist: 'Artist',
                    album: 'Album',
                    durationMs: 100000,
                    genre: const Value('House'),
                    isFavorite: const Value(true),
                    dateAdded: Value(i == 0 ? now : old),
                    lastPlayed: Value(i == 2 ? now : null),
                    startCount: Value(i == 1 ? 2 : 0),
                    skipCount: Value(i == 1 ? 1 : 0),
                  ),
                ),
          );
        }
        await db
            .into(db.listeningSessions)
            .insert(
              ListeningSessionsCompanion.insert(
                trackId: ids[1],
                startedAt: Value(DateTime(2026, 1, 1, 9, 30)),
                listenedMs: const Value(90 * 60000),
              ),
            );
        final data = await container.read(listeningExtrasProvider.future);
        expect((data['forgotten'] as List<Track>).map((t) => t.id), [ids[1]]);
        final hours = data['hours'] as List<int>;
        expect(hours[9], 30 * 60000);
        expect(hours[10], 60 * 60000);
        expect(data['genres'], {'House': 90 * 60000});
        expect((data['tracks'] as List<Track>).single.skipCount, 1);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );
  test('our MP3 rating takes precedence while other player frames survive', () {
    final audio = Uint8List.fromList([
      255,
      251,
      144,
      0,
      ...List.filled(300, 3),
    ]);
    final other = writeMp3Rating(audio, 4)..[20] = 120;
    expect(readMp3Rating(other), 4);
    final ours = writeMp3Rating(other, 1);
    expect(readMp3Rating(ours), 1);
    expect(
      ours.sublist(10, other.length - audio.length),
      other.sublist(10, other.length - audio.length),
    );
    expect(ours.sublist(ours.length - audio.length), audio);
  });
  test(
    'MP3 title and rating edits round trip together through the scanner',
    () async {
      final dir = await Directory.systemTemp.createTemp('electrowave_rating_');
      try {
        final file = await File(
          'test_files/same_song/2-add-after/Night Drive.mp3',
        ).copy('${dir.path}/rated.mp3');
        expect(
          applyTagEditToFile(
            file.path,
            const TagEdit(title: 'Rated title', rating: 3),
          ),
          TagFileResult.written,
        );
        final tags = parseTags(file.path);
        expect(tags.title, 'Rated title');
        expect(tags.rating, 3);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'MP3 ratings round trip without changing audio; repeat edits replace only our frame',
    () {
      final audio = Uint8List.fromList([
        255,
        251,
        144,
        0,
        ...List.generate(500, (i) => i % 256),
      ]);
      var tagged = writeMp3Rating(audio, 4);
      expect(readMp3Rating(tagged), 4);
      expect(tagged.sublist(tagged.length - audio.length), audio);
      final size = tagged.length;
      for (var stars = 0; stars <= 5; stars++) {
        tagged = writeMp3Rating(tagged, stars);
        expect(readMp3Rating(tagged), stars);
        expect(tagged.length, size);
        expect(tagged.sublist(tagged.length - audio.length), audio);
      }
      expect(
        () => writeMp3Rating(
          Uint8List.fromList([73, 68, 51, 4, 0, 128, 0, 0, 0, 0]),
          3,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'album artists split tagged albums while untagged compilations stay together',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        for (var i = 0; i < 4; i++) {
          await db
              .into(db.tracks)
              .insert(
                TracksCompanion.insert(
                  filePath: '/$i',
                  title: 'T$i',
                  artist: 'Artist $i',
                  album: 'Same name',
                  durationMs: 2000,
                  albumArtist: i < 2
                      ? const Value.absent()
                      : Value('Album artist $i'),
                ),
              );
        }
        final albums = await db.watchAlbums().first;
        expect(albums, hasLength(3));
        expect(
          albums.where((a) => a.albumArtist == null).single.artist,
          'Various artists',
        );
        for (final album in albums) {
          expect(
            (await db.watchAlbumTracks(album.key).first).length,
            album.trackCount,
          );
        }
      } finally {
        await db.close();
      }
    },
  );
  test(
    'restore matches a path suffix before changed tags and retains playlists and history',
    () async {
      final dir = await Directory.systemTemp.createTemp('electrowave_relink_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final id = await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                filePath: '/old-phone/Music/Album/track.wav',
                title: 'User edited title',
                artist: 'Old artist',
                album: 'Album',
                durationMs: 3000,
              ),
            );
        await db.recordPlay(id);
        final list = await db.createPlaylistWithTracks('Keep', [id]);
        final folder = await Directory(
          '${dir.path}/Music/Album',
        ).create(recursive: true);
        final file = await File('${folder.path}/track.wav').create();
        expect(
          await db.upsertScannedTrack(
            TracksCompanion.insert(
              filePath: file.path,
              title: 'Original tag',
              artist: 'Tag artist',
              album: 'Album',
              durationMs: 3000,
            ),
          ),
          id,
        );
        expect(
          (await db.watchPlaylistTracks(list).first).single.totalPlayCount,
          1,
        );
        expect((await db.trackById(id))!.filePath, file.path);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'M3U supports Unicode, excludes remote URLs and includes duration metadata',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                filePath: '/music/Björk/Jóga.flac',
                title: 'Jóga',
                artist: 'Björk',
                album: 'Homogenic',
                durationMs: 300000,
              ),
            );
        final text = PlaylistFileService.encode(await db.watchLibrary().first);
        expect(text, contains('#EXTINF:300,Björk - Jóga'));
        expect(PlaylistFileService.paths(text), ['/music/Björk/Jóga.flac']);
        expect(
          PlaylistFileService.paths(
            '\ufeff#EXTM3U\nhttps://bad.example/song.mp3\nrelative/song.mp3\n',
          ),
          ['relative/song.mp3'],
        );
      } finally {
        await db.close();
      }
    },
  );
}
