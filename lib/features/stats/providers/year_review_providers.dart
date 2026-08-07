import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

DateTime _yearStart(int year) => DateTime(year);
DateTime _yearEnd(int year) => DateTime(year + 1);

final yearDailyListeningProvider =
    StreamProvider.family<List<DailyListening>, int>((ref, year) {
      return ref
          .watch(databaseProvider)
          .watchDailyListening(from: _yearStart(year), to: _yearEnd(year));
    });

final yearListenedMsProvider = StreamProvider.family<int, int>((ref, year) {
  return ref
      .watch(databaseProvider)
      .watchTotalListenedMs(from: _yearStart(year), to: _yearEnd(year));
});

final yearDistinctTracksProvider = StreamProvider.family<int, int>((ref, year) {
  return ref
      .watch(databaseProvider)
      .watchDistinctTracksPlayed(from: _yearStart(year), to: _yearEnd(year));
});

final yearTopTracksProvider =
    StreamProvider.family<List<TrackListeningStat>, int>((ref, year) {
      return ref
          .watch(databaseProvider)
          .watchTracksByListeningTime(
            from: _yearStart(year),
            to: _yearEnd(year),
            limit: 5,
          );
    });

final yearTopArtistsProvider = StreamProvider.family<List<TopArtistStat>, int>((
  ref,
  year,
) {
  return ref
      .watch(databaseProvider)
      .watchTopArtists(from: _yearStart(year), to: _yearEnd(year), limit: 5);
});

/// Everything the heatmap and the share card need that has to be derived from
/// the daily rows rather than queried.
class ListeningYearShape {
  const ListeningYearShape({
    required this.byDay,
    required this.busiestDay,
    required this.busiestDayMs,
    required this.activeDays,
    required this.longestStreak,
  });

  factory ListeningYearShape.from(List<DailyListening> days) {
    final byDay = <DateTime, int>{
      for (final entry in days)
        DateTime(entry.day.year, entry.day.month, entry.day.day):
            entry.listenedMs,
    };

    DateTime? busiest;
    var busiestMs = 0;
    for (final entry in byDay.entries) {
      if (entry.value > busiestMs) {
        busiestMs = entry.value;
        busiest = entry.key;
      }
    }

    // Longest run of consecutive days with any listening on them.
    final sorted = byDay.keys.toList()..sort();
    var longest = 0;
    var run = 0;
    DateTime? previous;
    for (final day in sorted) {
      run = previous != null && day.difference(previous).inDays == 1
          ? run + 1
          : 1;
      if (run > longest) longest = run;
      previous = day;
    }

    return ListeningYearShape(
      byDay: byDay,
      busiestDay: busiest,
      busiestDayMs: busiestMs,
      activeDays: byDay.length,
      longestStreak: longest,
    );
  }

  /// Local midnight → listened milliseconds. Days with no listening are absent.
  final Map<DateTime, int> byDay;
  final DateTime? busiestDay;
  final int busiestDayMs;
  final int activeDays;
  final int longestStreak;

  bool get isEmpty => byDay.isEmpty;
}

final yearShapeProvider = Provider.family<ListeningYearShape, int>((ref, year) {
  final days = ref.watch(yearDailyListeningProvider(year)).value ?? const [];
  return ListeningYearShape.from(days);
});

/// Years that actually have listening data, newest first, always including the
/// current one so the screen is never empty.
final listenedYearsProvider = Provider<List<int>>((ref) {
  final now = DateTime.now().year;
  return [for (var year = now; year >= now - 9; year--) year];
});
