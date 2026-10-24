import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

// ---------------------------------------------------------------------------
// One track
// ---------------------------------------------------------------------------

final trackStatsProvider = StreamProvider.family<TrackStats, int>((ref, id) {
  return ref.watch(databaseProvider).watchTrackStats(id);
});

/// How many months the per-track chart covers, the current one included.
const kTrackMonthSpan = 12;

/// First of the month [kTrackMonthSpan] - 1 months before [now]'s.
DateTime trackMonthsFrom(DateTime now) =>
    DateTime(now.year, now.month - (kTrackMonthSpan - 1));

final trackMonthlyListeningProvider =
    StreamProvider.family<List<MonthlyListening>, int>((ref, id) {
      return ref
          .watch(databaseProvider)
          .watchTrackMonthlyListening(
            id,
            from: trackMonthsFrom(DateTime.now()),
          );
    });

final trackSessionsProvider =
    StreamProvider.family<List<ListeningSessionEntry>, int>((ref, id) {
      return ref.watch(databaseProvider).watchTrackSessions(id, limit: 30);
    });

// ---------------------------------------------------------------------------
// Every track
// ---------------------------------------------------------------------------

enum TrackStatsSort { heard, plays, recent, title }

final everyTrackSortProvider = StateProvider<TrackStatsSort>(
  (ref) => TrackStatsSort.heard,
);

final trackTotalsProvider = StreamProvider<List<TrackTotals>>((ref) {
  return ref.watch(databaseProvider).watchTrackTotals();
});

/// [rows] in [sort] order, narrowed to those whose title, artist or album
/// contains [search]. Ties fall back to the other figure and then the title,
/// so the order is stable from one rebuild to the next.
List<TrackTotals> sortTrackTotals(
  List<TrackTotals> rows,
  TrackStatsSort sort, {
  String search = '',
}) {
  final needle = search.trim().toLowerCase();
  final out = [
    for (final row in rows)
      if (needle.isEmpty ||
          row.track.title.toLowerCase().contains(needle) ||
          row.track.artist.toLowerCase().contains(needle) ||
          row.track.album.toLowerCase().contains(needle))
        row,
  ];

  int byTitle(TrackTotals a, TrackTotals b) =>
      a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase());

  out.sort((a, b) {
    final primary = switch (sort) {
      TrackStatsSort.heard => b.listenedMs.compareTo(a.listenedMs) != 0
          ? b.listenedMs.compareTo(a.listenedMs)
          : b.plays.compareTo(a.plays),
      TrackStatsSort.plays => b.plays.compareTo(a.plays) != 0
          ? b.plays.compareTo(a.plays)
          : b.listenedMs.compareTo(a.listenedMs),
      TrackStatsSort.recent => _byRecent(a.track.lastPlayed, b.track.lastPlayed),
      TrackStatsSort.title => 0,
    };
    return primary != 0 ? primary : byTitle(a, b);
  });
  return out;
}

/// Newest first, never-played last.
int _byRecent(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

final everyTrackSortedProvider = Provider<AsyncValue<List<TrackTotals>>>((
  ref,
) {
  final sort = ref.watch(everyTrackSortProvider);
  return ref
      .watch(trackTotalsProvider)
      .whenData((rows) => sortTrackTotals(rows, sort));
});
