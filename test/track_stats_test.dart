import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:electrowave_mobile/core/database/database.dart';
import 'package:electrowave_mobile/features/stats/providers/track_stats_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Per-track figures: one track's record, and the every-track list.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> addTrack(String title, {String artist = 'Echo Unit'}) {
    return db.into(db.tracks).insert(
          TracksCompanion.insert(
            filePath: '/music/$title.mp3',
            title: title,
            artist: artist,
            album: 'Test Kit',
            durationMs: 200000,
          ),
        );
  }

  Future<void> play(int trackId, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await db.recordPlay(trackId);
    }
  }

  Future<void> listen(int trackId, int ms, DateTime at) async {
    await db.into(db.listeningSessions).insert(
          ListeningSessionsCompanion.insert(
            trackId: trackId,
            startedAt: Value(at),
            listenedMs: Value(ms),
          ),
        );
  }

  group('watchTrackStats', () {
    test('an untouched track reads as empty', () async {
      final id = await addTrack('Quiet');

      final stats = await db.watchTrackStats(id).first;

      expect(stats.untouched, isTrue);
      expect(stats.plays, 0);
      expect(stats.starts, 0);
      expect(stats.listenedMs, 0);
      expect(stats.playRank, isNull);
      expect(stats.firstSeen, isNull);
      expect(stats.lastSeen, isNull);
    });

    test('counts plays, starts and listening for that track only', () async {
      final mine = await addTrack('Mine');
      final other = await addTrack('Other');
      await play(mine, times: 3);
      await play(other);
      await listen(mine, 60000, DateTime(2026, 3, 4, 22));
      await listen(mine, 15000, DateTime(2026, 5, 1, 9));
      await listen(other, 99000, DateTime(2026, 5, 2));

      final stats = await db.watchTrackStats(mine).first;

      expect(stats.plays, 3);
      expect(stats.starts, 2);
      expect(stats.listenedMs, 75000);
      expect(stats.firstHeard, DateTime(2026, 3, 4, 22));
      expect(stats.lastHeard, DateTime(2026, 5, 1, 9));
      expect(stats.firstPlayed, isNotNull);
      expect(stats.lastPlayed, isNotNull);
    });

    test('ranks by plays, with ties sharing a place', () async {
      final top = await addTrack('Top');
      final tiedA = await addTrack('Tied A');
      final tiedB = await addTrack('Tied B');
      final last = await addTrack('Last');
      await play(top, times: 5);
      await play(tiedA, times: 2);
      await play(tiedB, times: 2);
      await play(last);

      expect((await db.watchTrackStats(top).first).playRank, 1);
      expect((await db.watchTrackStats(tiedA).first).playRank, 2);
      expect((await db.watchTrackStats(tiedB).first).playRank, 2);
      expect((await db.watchTrackStats(last).first).playRank, 4);
    });

    test('a removed track does not hold a place in the rank', () async {
      final removed = await addTrack('Removed');
      final kept = await addTrack('Kept');
      await play(removed, times: 9);
      await play(kept, times: 2);
      await db.softDeleteTrack(removed);

      expect((await db.watchTrackStats(kept).first).playRank, 1);
    });
  });

  test('watchTrackMonthlyListening groups by local month from the start',
      () async {
    final id = await addTrack('Monthly');
    await listen(id, 1000, DateTime(2025, 12, 31, 23));
    await listen(id, 2000, DateTime(2026, 1, 2));
    await listen(id, 3000, DateTime(2026, 1, 30));
    await listen(id, 4000, DateTime(2026, 3, 1));

    final months = await db
        .watchTrackMonthlyListening(id, from: DateTime(2026))
        .first;
    final byMonth = {for (final m in months) m.month: m.listenedMs};

    expect(byMonth, {DateTime(2026): 5000, DateTime(2026, 3): 4000});
  });

  test('watchTrackSessions is newest first and limited', () async {
    final id = await addTrack('Sessions');
    for (var day = 1; day <= 5; day++) {
      await listen(id, day * 1000, DateTime(2026, 2, day));
    }

    final sessions = await db.watchTrackSessions(id, limit: 3).first;

    expect([for (final s in sessions) s.listenedMs], [5000, 4000, 3000]);
  });

  group('every track', () {
    test('lists every library track, unplayed included, removed left out',
        () async {
      final heard = await addTrack('Heard');
      final unplayed = await addTrack('Unplayed');
      final removed = await addTrack('Removed');
      await listen(heard, 30000, DateTime(2026, 1, 1));
      await listen(heard, 12000, DateTime(2026, 1, 2));
      await db.softDeleteTrack(removed);

      final rows = await db.watchTrackTotals().first;
      final byId = {for (final r in rows) r.track.id: r};

      expect(byId.keys, unorderedEquals([heard, unplayed]));
      expect(byId[heard]!.listenedMs, 42000);
      expect(byId[unplayed]!.untouched, isTrue);
    });

    test('sorts and filters', () async {
      final a = await addTrack('alpha', artist: 'Zed');
      final b = await addTrack('Bravo', artist: 'Yan');
      await addTrack('charlie', artist: 'Xu');
      await play(a, times: 1);
      await play(b, times: 4);
      await listen(a, 90000, DateTime(2026, 1, 1));
      await listen(b, 10000, DateTime(2026, 1, 1));

      final rows = await db.watchTrackTotals().first;
      List<String> titles(TrackStatsSort sort, [String search = '']) => [
            for (final r in sortTrackTotals(rows, sort, search: search))
              r.track.title,
          ];

      expect(titles(TrackStatsSort.heard), ['alpha', 'Bravo', 'charlie']);
      expect(titles(TrackStatsSort.plays), ['Bravo', 'alpha', 'charlie']);
      expect(titles(TrackStatsSort.title), ['alpha', 'Bravo', 'charlie']);
      // Unplayed tracks have no last-played date and sink to the bottom.
      expect(titles(TrackStatsSort.recent).last, 'charlie');
      expect(titles(TrackStatsSort.title, 'yan'), ['Bravo']);
      expect(titles(TrackStatsSort.title, '  KIT '), hasLength(3));
    });
  });
}
