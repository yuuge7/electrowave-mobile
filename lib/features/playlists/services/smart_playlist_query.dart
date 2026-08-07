import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../models/smart_playlist.dart';

/// Measured listening time per track, as a scalar subquery.
///
/// [ListeningSessions] holds one row per stretch played, so a rule on "time
/// listened" has to aggregate them. Written by hand rather than through a
/// join: joining would multiply the track rows and every other rule would then
/// have to be aggregate-aware.
final _listenedMsExpression = CustomExpression<int>(
  '(SELECT COALESCE(SUM(listened_ms), 0) FROM listening_sessions '
  'WHERE listening_sessions.track_id = tracks.id)',
);

/// SQLite's own shuffle. A watched query re-runs whenever the library
/// changes, so a random smart playlist reshuffles on edits rather than being
/// a stable order — which is what "random" is expected to do here.
const _randomExpression = CustomExpression<int>('RANDOM()');

/// Live tracks matching [definition], newest state of the library included.
Stream<List<Track>> watchSmartPlaylistTracks(
  AppDatabase db,
  SmartPlaylistDefinition definition,
) {
  final tracks = db.tracks;
  final query = db.select(tracks)..where((t) => t.isDeleted.equals(false));

  final conditions = [
    for (final rule in definition.rules) ?_condition(tracks, rule),
  ];
  if (conditions.isNotEmpty) {
    // An "any" list with no usable rules would otherwise match nothing.
    final combined = definition.matchAll
        ? conditions.reduce((a, b) => a & b)
        : conditions.reduce((a, b) => a | b);
    query.where((_) => combined);
  }

  query.orderBy([(t) => _ordering(t, definition)]);
  final limit = definition.limit;
  if (limit != null && limit > 0) query.limit(limit);

  return query.watch();
}

OrderingTerm _ordering(Tracks t, SmartPlaylistDefinition definition) {
  final mode = definition.descending ? OrderingMode.desc : OrderingMode.asc;
  return switch (definition.sort) {
    SmartSort.title => OrderingTerm(
      expression: t.title.collate(Collate.noCase),
      mode: mode,
    ),
    SmartSort.artist => OrderingTerm(
      expression: t.artist.collate(Collate.noCase),
      mode: mode,
    ),
    SmartSort.dateAdded => OrderingTerm(expression: t.dateAdded, mode: mode),
    SmartSort.playCount => OrderingTerm(
      expression: t.totalPlayCount,
      mode: mode,
    ),
    SmartSort.lastPlayed => OrderingTerm(expression: t.lastPlayed, mode: mode),
    SmartSort.listenedTime => OrderingTerm(
      expression: _listenedMsExpression,
      mode: mode,
    ),
    // Ordering a shuffle by direction is meaningless.
    SmartSort.random => OrderingTerm(expression: _randomExpression),
  };
}

/// Null when the rule can't be applied (a number field left blank, say), which
/// drops it rather than matching everything or nothing.
Expression<bool>? _condition(Tracks t, SmartRule rule) {
  final raw = rule.value.trim();

  switch (rule.field.kind) {
    case SmartFieldKind.text:
      if (raw.isEmpty) return null;
      final column = switch (rule.field) {
        SmartField.title => t.title,
        SmartField.artist => t.artist,
        SmartField.album => t.album,
        // Untagged genres are null, and LIKE on null is null — the row simply
        // doesn't match, which is the wanted behaviour for both operators.
        _ => t.genre,
      };
      return switch (rule.operator) {
        SmartOperator.contains => column.like('%$raw%'),
        // Case-insensitive so "House" and "house" are one genre.
        _ => column.lower().equals(raw.toLowerCase()),
      };

    case SmartFieldKind.number:
      final value = num.tryParse(raw);
      if (value == null) return null;
      final (Expression<int> column, int scaled) = switch (rule.field) {
        SmartField.year => (t.year, value.toInt()),
        SmartField.durationMinutes => (
          t.durationMs,
          (value * Duration.millisecondsPerMinute).round(),
        ),
        SmartField.playCount => (t.totalPlayCount, value.toInt()),
        _ => (
          _listenedMsExpression,
          (value * Duration.millisecondsPerMinute).round(),
        ),
      };
      return switch (rule.operator) {
        SmartOperator.greaterThan => column.isBiggerThanValue(scaled),
        SmartOperator.lessThan => column.isSmallerThanValue(scaled),
        _ => column.equals(scaled),
      };

    case SmartFieldKind.date:
      final column = rule.field == SmartField.lastPlayed
          ? t.lastPlayed
          : t.dateAdded;
      if (rule.operator == SmartOperator.never) return column.isNull();
      final days = int.tryParse(raw);
      if (days == null || days < 0) return null;
      final since = DateTime.now().subtract(Duration(days: days));
      return switch (rule.operator) {
        SmartOperator.within => column.isBiggerOrEqualValue(since),
        // "Not in the last N days" covers never-played tracks too: they have
        // not been played in that window either.
        _ => column.isSmallerThanValue(since) | column.isNull(),
      };

    case SmartFieldKind.boolean:
      return t.isFavorite.equals(rule.operator == SmartOperator.isTrue);
  }
}
