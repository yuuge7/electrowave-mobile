import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../player/providers/player_providers.dart';
import '../providers/stats_providers.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(statsPeriodProvider);
    final totalMs = ref.watch(totalListeningMsProvider).value ?? 0;
    final topTracks = ref.watch(topTracksProvider).value ?? const [];
    final topArtists = ref.watch(topArtistsProvider).value ?? const [];
    final byListeningTime =
        ref.watch(tracksByListeningTimeProvider).value ?? const [];
    final listenedMs = ref.watch(totalListenedMsProvider).value ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Wrapped'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Year in review',
            onPressed: () => context.push(
              '/stats/year/${period.year ?? DateTime.now().year}',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _PeriodPicker(period: period),
          ),
          // Total listening time
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.headphones, size: 40, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    formatListeningTime(Duration(milliseconds: totalMs)),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'listened ${_periodLabel(period)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (topTracks.isEmpty && topArtists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No listens in this period yet.\nPlay something!',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (topTracks.isNotEmpty) ...[
            _sectionHeader(context, 'Top tracks'),
            for (final (index, stat) in topTracks.take(10).indexed)
              ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                      ArtThumb(artPath: stat.track.albumArtPath, size: 44),
                    ],
                  ),
                ),
                title: Text(
                  stat.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  stat.track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${stat.playCount} plays'),
                onTap: () =>
                    ref.read(playerControllerProvider.notifier).playFromList(
                      stat.track,
                      [for (final s in topTracks) s.track],
                      'Top tracks',
                    ),
              ),
          ],
          if (byListeningTime.isNotEmpty) ...[
            _sectionHeader(context, 'Time listened'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Time you actually spent listening, measured from playback — '
                'skips and unfinished tracks count only for the part you '
                'heard, and a track played at 1.5× costs less of it than the '
                'same track at 1×. '
                '${formatListeningTime(Duration(milliseconds: listenedMs))} '
                'in total.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            for (final (index, stat) in byListeningTime.take(10).indexed)
              ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                      ArtThumb(artPath: stat.track.albumArtPath, size: 44),
                    ],
                  ),
                ),
                title: Text(
                  stat.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  stat.track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  formatListeningTime(Duration(milliseconds: stat.listenedMs)),
                ),
                onTap: () =>
                    ref.read(playerControllerProvider.notifier).playFromList(
                      stat.track,
                      [for (final s in byListeningTime) s.track],
                      'Time listened',
                    ),
              ),
          ],
          if (topArtists.isNotEmpty) ...[
            _sectionHeader(context, 'Top artists'),
            for (final (index, stat) in topArtists.take(10).indexed)
              ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                      CircleAvatar(
                        child: Text(
                          stat.artist.isNotEmpty
                              ? stat.artist[0].toUpperCase()
                              : '?',
                        ),
                      ),
                    ],
                  ),
                ),
                title: Text(
                  stat.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  formatListeningTime(Duration(milliseconds: stat.totalMs)),
                ),
                trailing: Text('${stat.playCount} plays'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  String _periodLabel(StatsPeriod period) {
    switch (period.kind) {
      case StatsPeriodKind.allTime:
        return 'all time';
      case StatsPeriodKind.year:
        return 'in ${period.year}';
      case StatsPeriodKind.month:
        return 'in ${DateFormat.yMMMM().format(DateTime(period.year!, period.month!))}';
    }
  }
}

class _PeriodPicker extends ConsumerWidget {
  const _PeriodPicker({required this.period});

  final StatsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final years = [for (var y = now.year; y >= now.year - 9; y--) y];
    final notifier = ref.read(statsPeriodProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<StatsPeriodKind>(
          segments: const [
            ButtonSegment(
              value: StatsPeriodKind.allTime,
              label: Text('All time'),
            ),
            ButtonSegment(value: StatsPeriodKind.year, label: Text('Year')),
            ButtonSegment(value: StatsPeriodKind.month, label: Text('Month')),
          ],
          selected: {period.kind},
          onSelectionChanged: (selection) {
            switch (selection.first) {
              case StatsPeriodKind.allTime:
                notifier.state = const StatsPeriod.allTime();
              case StatsPeriodKind.year:
                notifier.state = StatsPeriod.year(period.year ?? now.year);
              case StatsPeriodKind.month:
                notifier.state = StatsPeriod.month(
                  period.year ?? now.year,
                  period.month ?? now.month,
                );
            }
          },
        ),
        if (period.kind != StatsPeriodKind.allTime)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: period.year,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (year) {
                      if (year == null) return;
                      notifier.state = period.kind == StatsPeriodKind.year
                          ? StatsPeriod.year(year)
                          : StatsPeriod.month(year, period.month ?? 1);
                    },
                  ),
                ),
                if (period.kind == StatsPeriodKind.month) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: period.month,
                      decoration: const InputDecoration(
                        labelText: 'Month',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              DateFormat.MMM().format(DateTime(2000, m)),
                            ),
                          ),
                      ],
                      onChanged: (month) {
                        if (month == null) return;
                        notifier.state = StatsPeriod.month(
                          period.year ?? now.year,
                          month,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
