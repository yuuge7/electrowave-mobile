import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

enum StatsPeriodKind { allTime, year, month }

class StatsPeriod {
  const StatsPeriod.allTime()
      : kind = StatsPeriodKind.allTime,
        year = null,
        month = null;

  const StatsPeriod.year(int this.year)
      : kind = StatsPeriodKind.year,
        month = null;

  const StatsPeriod.month(int this.year, int this.month)
      : kind = StatsPeriodKind.month;

  final StatsPeriodKind kind;
  final int? year;
  final int? month;

  DateTime? get from {
    switch (kind) {
      case StatsPeriodKind.allTime:
        return null;
      case StatsPeriodKind.year:
        return DateTime(year!);
      case StatsPeriodKind.month:
        return DateTime(year!, month!);
    }
  }

  DateTime? get to {
    switch (kind) {
      case StatsPeriodKind.allTime:
        return null;
      case StatsPeriodKind.year:
        return DateTime(year! + 1);
      case StatsPeriodKind.month:
        return month == 12 ? DateTime(year! + 1) : DateTime(year!, month! + 1);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StatsPeriod &&
      other.kind == kind &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(kind, year, month);
}

final statsPeriodProvider =
    StateProvider<StatsPeriod>((ref) => const StatsPeriod.allTime());

final totalListeningMsProvider = StreamProvider<int>((ref) {
  final period = ref.watch(statsPeriodProvider);
  return ref
      .watch(databaseProvider)
      .watchTotalListeningMs(from: period.from, to: period.to);
});

final topTracksProvider = StreamProvider<List<TopTrackStat>>((ref) {
  final period = ref.watch(statsPeriodProvider);
  return ref
      .watch(databaseProvider)
      .watchTopTracks(from: period.from, to: period.to, limit: 25);
});

/// Measured listening time per track — counts audio that actually played,
/// unlike [topTracksProvider] which ranks by number of plays.
final tracksByListeningTimeProvider =
    StreamProvider<List<TrackListeningStat>>((ref) {
  final period = ref.watch(statsPeriodProvider);
  return ref
      .watch(databaseProvider)
      .watchTracksByListeningTime(from: period.from, to: period.to, limit: 25);
});

final totalListenedMsProvider = StreamProvider<int>((ref) {
  final period = ref.watch(statsPeriodProvider);
  return ref
      .watch(databaseProvider)
      .watchTotalListenedMs(from: period.from, to: period.to);
});

final topArtistsProvider = StreamProvider<List<TopArtistStat>>((ref) {
  final period = ref.watch(statsPeriodProvider);
  return ref
      .watch(databaseProvider)
      .watchTopArtists(from: period.from, to: period.to, limit: 25);
});
