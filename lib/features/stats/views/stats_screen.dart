import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart' as type;
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../../shared/widgets/state_views.dart';
import '../../player/providers/player_providers.dart';
import '../providers/stats_providers.dart';

/// Listening figures.
///
/// The screen is built around the one thing this app knows that a streaming
/// service's year-end summary does not: it measures two different things and
/// they disagree on purpose. `PlaybackHistory` says a play happened and
/// counts the track's whole length; `ListeningSessions` counts the audio that
/// actually came out. A track you skip forty seconds into books a full play
/// and forty seconds of listening.
///
/// That gap used to be explained in a paragraph of small text between two
/// unrelated lists. Here it is a column: every ranked track shows what it
/// claims and what it actually cost you.
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

    // Measured time keyed by track, so a ranked row can show both figures.
    final heard = {
      for (final stat in byListeningTime) stat.track.id: stat.listenedMs,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_month_outlined),
            tooltip: 'Year in review',
            onPressed: () => context.push(
              '/stats/year/${period.year ?? DateTime.now().year}',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: _PeriodPicker(period: period),
          ),
          _Headline(
            totalMs: totalMs,
            listenedMs: listenedMs,
            period: period,
          ),
          if (topTracks.isEmpty && topArtists.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyStateView(
                icon: Icons.equalizer_outlined,
                title: 'Nothing logged yet',
                message: 'A track counts once you have actually heard a '
                    'quarter of it, so play something and come back.',
                compact: true,
              ),
            ),
          if (topTracks.isNotEmpty) ...[
            const SectionHeader('Most played'),
            _Caption(
              'Ranked by plays. The second figure is what you really heard — '
              'where they diverge, you have been skipping.',
            ),
            for (final (index, stat) in topTracks.take(10).indexed)
              _RankRow(
                rank: index + 1,
                title: stat.track.title,
                subtitle: stat.track.artist,
                artPath: stat.track.albumArtPath,
                seed: stat.track.album.isNotEmpty
                    ? stat.track.album
                    : stat.track.title,
                value: stat.playCount.toDouble(),
                maxValue: topTracks.first.playCount.toDouble(),
                primary: '${stat.playCount} '
                    'play${stat.playCount == 1 ? '' : 's'}',
                secondary: heard[stat.track.id] == null
                    ? null
                    : '${formatListeningTime(
                        Duration(milliseconds: heard[stat.track.id]!),
                      )} heard',
                onTap: () =>
                    ref.read(playerControllerProvider.notifier).playFromList(
                          stat.track,
                          [for (final s in topTracks) s.track],
                          'Most played',
                        ),
              ),
          ],
          if (byListeningTime.isNotEmpty) ...[
            const SectionHeader('Time actually heard'),
            _Caption(
              'Measured from playback, not inferred from play counts. Speed '
              'counts as real time: a 1:00 track is 0:40 at 1.5×.',
            ),
            for (final (index, stat) in byListeningTime.take(10).indexed)
              _RankRow(
                rank: index + 1,
                title: stat.track.title,
                subtitle: stat.track.artist,
                artPath: stat.track.albumArtPath,
                seed: stat.track.album.isNotEmpty
                    ? stat.track.album
                    : stat.track.title,
                value: stat.listenedMs.toDouble(),
                maxValue: byListeningTime.first.listenedMs.toDouble(),
                primary: formatListeningTime(
                  Duration(milliseconds: stat.listenedMs),
                ),
                onTap: () =>
                    ref.read(playerControllerProvider.notifier).playFromList(
                          stat.track,
                          [for (final s in byListeningTime) s.track],
                          'Time heard',
                        ),
              ),
          ],
          if (topArtists.isNotEmpty) ...[
            const SectionHeader('Most played artists'),
            for (final (index, stat) in topArtists.take(10).indexed)
              _RankRow(
                rank: index + 1,
                title: stat.artist,
                subtitle: '${stat.playCount} '
                    'play${stat.playCount == 1 ? '' : 's'}',
                seed: stat.artist,
                value: stat.totalMs.toDouble(),
                maxValue: topArtists.first.totalMs.toDouble(),
                primary: formatListeningTime(
                  Duration(milliseconds: stat.totalMs),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Headline
// ---------------------------------------------------------------------------

/// The period's totals as a counter, the same readout the player uses. Both
/// numbers sit together because the difference between them is the point.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.totalMs,
    required this.listenedMs,
    required this.period,
  });

  final int totalMs;
  final int listenedMs;
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.hairline),
        color: scheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelLabel('Played · ${_periodLabel(period)}'),
          const SizedBox(height: 12),
          Text(
            formatListeningTime(Duration(milliseconds: totalMs)),
            style: type.counter(38).copyWith(color: tokens.signal),
          ),
          const SizedBox(height: 16),
          Divider(color: tokens.hairline, height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PanelLabel('Actually heard'),
                    const SizedBox(height: 8),
                    Text(
                      formatListeningTime(Duration(milliseconds: listenedMs)),
                      style: type.counter(20, weight: 400)
                          .copyWith(color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
              if (totalMs > 0)
                _Divergence(totalMs: totalMs, listenedMs: listenedMs),
            ],
          ),
        ],
      ),
    );
  }
}

/// How much of what was "played" was actually heard. Amber when a lot of it
/// was not, because that is the interesting case.
class _Divergence extends StatelessWidget {
  const _Divergence({required this.totalMs, required this.listenedMs});

  final int totalMs;
  final int listenedMs;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final ratio = (listenedMs / totalMs).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final color = ratio < 0.6 ? tokens.peak : tokens.signal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$percent%',
          style: type.counter(20, weight: 400).copyWith(color: color),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 92,
          child: SignalRule(value: ratio, color: color, radius: 1),
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ranked row
// ---------------------------------------------------------------------------

/// A ranked row with its value drawn as a bar rather than left as a number to
/// compare by eye. Ten rows of "12 plays / 9 plays / 7 plays" is a table; the
/// bar is what makes it a chart.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.seed,
    required this.value,
    required this.maxValue,
    required this.primary,
    this.artPath,
    this.secondary,
    this.onTap,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String seed;
  final double value;
  final double maxValue;
  final String primary;
  final String? artPath;
  final String? secondary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.deck;
    final fraction = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '$rank',
                      style: type
                          .instrument(12, weight: 500)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (artPath != null || rank > 0)
                    ArtThumb(
                      artPath: artPath,
                      size: 38,
                      borderRadius: 6,
                      seed: seed,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The figures are numbers and cannot be ellipsized, so at a
                  // large text scale they crowded the title out of the row and
                  // then ran past it. Cap them at a third of the row and let
                  // them shrink to fit that instead.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 3,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            primary,
                            style: type
                                .instrument(11, weight: 500)
                                .copyWith(color: scheme.onSurface),
                          ),
                          if (secondary != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              secondary!,
                              style: type
                                  .instrument(9.5)
                                  .copyWith(color: tokens.peak),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: SignalRule(
                value: fraction,
                height: 3,
                color: tokens.signalDim,
                radius: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period
// ---------------------------------------------------------------------------

class _PeriodPicker extends ConsumerWidget {
  const _PeriodPicker({required this.period});

  final StatsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
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
          showSelectedIcon: false,
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
        // Years and months are a short, ordered list, so a scrolling rail of
        // them beats two dropdowns lifted off a web form: one tap instead of
        // three, and you can see where you are in the range.
        if (period.kind != StatsPeriodKind.allTime)
          _Rail(
            values: [for (var y = now.year; y >= now.year - 9; y--) '$y'],
            selected: '${period.year ?? now.year}',
            onSelected: (value) {
              final year = int.parse(value);
              notifier.state = period.kind == StatsPeriodKind.year
                  ? StatsPeriod.year(year)
                  : StatsPeriod.month(year, period.month ?? 1);
            },
          ),
        if (period.kind == StatsPeriodKind.month)
          _Rail(
            values: [
              for (var m = 1; m <= 12; m++)
                DateFormat.MMM().format(DateTime(2000, m)),
            ],
            selected: DateFormat.MMM().format(
              DateTime(2000, period.month ?? 1),
            ),
            onSelected: (value) {
              final month = 1 +
                  [
                    for (var m = 1; m <= 12; m++)
                      DateFormat.MMM().format(DateTime(2000, m)),
                  ].indexOf(value);
              notifier.state = StatsPeriod.month(
                period.year ?? now.year,
                month,
              );
            },
          ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final value = values[index];
          final isSelected = value == selected;
          return InkWell(
            onTap: () => onSelected(value),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? tokens.signal.withValues(alpha: 0.6)
                      : scheme.outline.withValues(alpha: 0.4),
                ),
                color: isSelected
                    ? tokens.signal.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: Text(
                value,
                style: type.instrument(11, weight: 500).copyWith(
                      color:
                          isSelected ? tokens.signal : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _periodLabel(StatsPeriod period) {
  switch (period.kind) {
    case StatsPeriodKind.allTime:
      return 'all time';
    case StatsPeriodKind.year:
      return '${period.year}';
    case StatsPeriodKind.month:
      return DateFormat.yMMMM().format(
        DateTime(period.year!, period.month!),
      );
  }
}
