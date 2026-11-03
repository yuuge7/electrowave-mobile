import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../library/views/track_list_screen.dart';

final listeningExtrasProvider = FutureProvider.autoDispose<Map<String, Object>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);
  final tracks = await db.watchLibrary().first;
  final sessions = await db.select(db.listeningSessions).get();
  final byId = {for (final t in tracks) t.id: t};
  final hours = List<int>.filled(24, 0);
  final genres = <String, int>{};
  // Split sessions at each hour boundary instead of attributing a long mix to its start.
  for (final session in sessions) {
    var start = session.startedAt;
    var remaining = session.listenedMs;
    while (remaining > 0) {
      final boundary = DateTime(
        start.year,
        start.month,
        start.day,
        start.hour + 1,
      );
      final part = remaining.clamp(
        0,
        boundary.difference(start).inMilliseconds,
      );
      hours[start.hour] += part;
      remaining -= part;
      start = boundary;
    }
    final genre = byId[session.trackId]?.genre ?? 'Unknown genre';
    genres.update(
      genre,
      (v) => v + session.listenedMs,
      ifAbsent: () => session.listenedMs,
    );
  }
  final cutoff = DateTime.now().subtract(const Duration(days: 183));
  final forgotten = tracks
      .where(
        (t) =>
            (t.isFavorite || t.totalPlayCount >= 10) &&
            (t.lastPlayed ?? t.dateAdded).isBefore(cutoff),
      )
      .toList();
  return {
    'hours': hours,
    'genres': genres,
    'forgotten': forgotten,
    'tracks': tracks.where((t) => t.startCount > 0).toList(),
  };
});

class ListeningExtrasScreen extends ConsumerWidget {
  const ListeningExtrasScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(listeningExtrasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening patterns')),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          final hours = data['hours'] as List<int>;
          final genres = (data['genres'] as Map<String, int>).entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final tracks = data['tracks'] as List<Track>;
          tracks.sort(
            (a, b) => (b.skipCount / b.startCount).compareTo(
              a.skipCount / a.startCount,
            ),
          );
          final forgotten = data['forgotten'] as List<Track>;
          final peak = hours.fold<int>(0, (a, b) => a > b ? a : b);
          return ListView.builder(
            itemCount: 28 + genres.length + tracks.length,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const ListTile(
                  title: Text('Listening by hour'),
                  subtitle: Text('Measured time, in local time'),
                );
              }
              if (index <= 24) {
                final i = index - 1;
                return ListTile(
                  dense: true,
                  title: Text('${i.toString().padLeft(2, '0')}:00'),
                  subtitle: LinearProgressIndicator(
                    value: peak == 0 ? 0 : hours[i] / peak,
                  ),
                  trailing: Text('${(hours[i] / 60000).round()} min'),
                );
              }
              if (index == 25) return const ListTile(title: Text('Genres'));
              if (index < 26 + genres.length) {
                final g = genres[index - 26];
                return ListTile(
                  title: Text(g.key),
                  trailing: Text('${(g.value / 60000).round()} min'),
                );
              }
              if (index == 26 + genres.length) {
                return ListTile(
                  title: const Text('Forgotten favourites'),
                  subtitle: Text(
                    '${forgotten.length} loved or often played tracks unheard for six months',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrackListScreen(
                        title: 'Forgotten favourites',
                        tracks: AsyncValue.data(forgotten),
                      ),
                    ),
                  ),
                );
              }
              if (index == 27 + genres.length) {
                return const ListTile(
                  title: Text('Skip rate'),
                  subtitle: Text(
                    'Manual skips / starts recorded since this update',
                  ),
                );
              }
              final t = tracks[index - 28 - genres.length];
              return ListTile(
                title: Text(t.title),
                subtitle: Text(t.artist),
                trailing: Text(
                  '${(100 * t.skipCount / t.startCount).clamp(0, 100).round()}% · ${t.skipCount}/${t.startCount}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
