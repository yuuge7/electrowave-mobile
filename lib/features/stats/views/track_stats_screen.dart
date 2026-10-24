import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart' as type;
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../../library/providers/browse_providers.dart';
import '../../player/providers/player_providers.dart';
import '../../player/services/listening_meter.dart';
import '../providers/track_stats_providers.dart';

/// One track's whole record.
///
/// Same two truths as the Stats tab, for a single song: how often it was
/// played, and how much of it actually came out of the speakers. The list of
/// recent listens is where the difference shows — every start gets a bar the
/// length of what you heard, so a habit of skipping the intro or bailing
/// before the bridge is visible at a glance.
class TrackStatsScreen extends ConsumerWidget {
  const TrackStatsScreen({super.key, required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(trackStreamProvider(trackId));
    final track = trackAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track stats'),
        actions: [
          if (track != null) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play',
              onPressed: () => ref
                  .read(playerControllerProvider.notifier)
                  .playFromList(track, [track], 'Track stats'),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More actions',
              onPressed: () => showTrackContextMenu(
                context,
                track,
                showStats: false,
              ),
            ),
          ],
        ],
      ),
      body: AsyncView<Track?>(
        value: trackAsync,
        data: (track) => track == null
            ? const EmptyStateView(
                icon: Icons.music_off_outlined,
                title: 'Track not found',
                message: 'It is no longer in the library.',
              )
            : _Body(track: track),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats =
        ref.watch(trackStatsProvider(track.id)).value ?? TrackStats.empty;
    final months =
        ref.watch(trackMonthlyListeningProvider(track.id)).value ?? const [];
    final sessions =
        ref.watch(trackSessionsProvider(track.id)).value ?? const [];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _TrackHeader(track: track),
        _Headline(track: track, stats: stats),
        if (stats.untouched)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyStateView(
              icon: Icons.equalizer_outlined,
              title: 'Not played yet',
              message: 'Listening is logged as it happens. A play counts once '
                  'a quarter of the track has gone past.',
              compact: true,
            ),
          )
        else ...[
          const SectionHeader('Breakdown'),
          _Figures(track: track, stats: stats),
          const SectionHeader('Last 12 months'),
          _MonthBars(months: months),
          if (sessions.isNotEmpty) ...[
            SectionHeader(
              'Recent listens',
              trailing: Text(
                '${sessions.length}',
                style: type
                    .instrument(10, weight: 500)
                    .copyWith(color: context.deck.panel),
              ),
            ),
            const _Caption(
              'Each time it was started, and how much of it you heard. '
              'Amber ones stopped before they counted as a play.',
            ),
            for (final session in sessions)
              _SessionRow(session: session, track: track),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      track.artist,
      if (track.album.isNotEmpty) track.album,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          ArtThumb(
            artPath: track.albumArtPath,
            size: 64,
            borderRadius: 8,
            seed: track.album.isNotEmpty ? track.album : track.title,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Headline
// ---------------------------------------------------------------------------

/// Heard time large, plays beside it, and the share of "played" that was
/// really heard — the same card as the Stats tab, scoped to one song.
class _Headline extends StatelessWidget {
  const _Headline({required this.track, required this.stats});

  final Track track;
  final TrackStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final playedMs = stats.plays * track.durationMs;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.hairline),
        color: scheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelLabel('Actually heard · all time'),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatListeningTime(Duration(milliseconds: stats.listenedMs)),
              style: type.counter(38).copyWith(
                color: stats.untouched
                    ? scheme.onSurfaceVariant
                    : tokens.signal,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: tokens.hairline, height: 1),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _Figure(
                    value: '${stats.plays}',
                    label: stats.plays == 1 ? 'play' : 'plays',
                  ),
                ),
                if (playedMs > 0)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _Coverage(
                        ratio: stats.listenedMs / playedMs,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of what its plays add up to was actually heard. Amber when a lot
/// of it was not, the same threshold the Stats tab uses.
class _Coverage extends StatelessWidget {
  const _Coverage({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final clamped = ratio.clamp(0.0, 1.0);
    final color = clamped < 0.6 ? tokens.peak : tokens.signal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(clamped * 100).round()}%',
          style: type.counter(20, weight: 400).copyWith(color: color),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 92,
          child: SignalRule(value: clamped, color: color, radius: 1),
        ),
        const SizedBox(height: 6),
        Text(
          'OF PLAYED',
          style: type.panelLabel().copyWith(color: tokens.panel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Breakdown
// ---------------------------------------------------------------------------

class _Figures extends StatelessWidget {
  const _Figures({required this.track, required this.stats});

  final Track track;
  final TrackStats stats;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd();
    final duration = track.durationMs;

    final cells = <_Figure>[
      _Figure(
        value: '${stats.starts}',
        label: stats.starts == 1 ? 'start' : 'starts',
      ),
      if (duration > 0)
        _Figure(
          value: (stats.listenedMs / duration).toStringAsFixed(1),
          label: 'full listens',
        ),
      if (stats.starts > 0)
        _Figure(
          value: formatListeningTime(
            Duration(milliseconds: stats.listenedMs ~/ stats.starts),
          ),
          label: 'avg per start',
        ),
      if (stats.playRank != null)
        _Figure(value: 'No. ${stats.playRank}', label: 'by plays'),
      if (stats.firstSeen != null)
        _Figure(value: date.format(stats.firstSeen!), label: 'first played'),
      if (stats.lastSeen != null)
        _Figure(value: date.format(stats.lastSeen!), label: 'last played'),
      _Figure(value: date.format(track.dateAdded), label: 'added'),
      if (duration > 0)
        _Figure(value: formatDurationMs(duration), label: 'length'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Column(
        children: [
          for (var i = 0; i < cells.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cells[i]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: i + 1 < cells.length
                        ? cells[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A figure over its engraved label.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: type
                .counter(20, weight: 400)
                .copyWith(color: scheme.onSurface),
          ),
        ),
        const SizedBox(height: 5),
        PanelLabel(label),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Months
// ---------------------------------------------------------------------------

/// Measured listening per month, oldest on the left. Bars are relative to the
/// busiest month, so the shape reads the same for a song heard twice as for
/// one on repeat.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.months});

  final List<MonthlyListening> months;

  static const double _barHeight = 64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final start = trackMonthsFrom(now);
    final byMonth = {for (final m in months) m.month: m.listenedMs};
    final slots = [
      for (var i = 0; i < kTrackMonthSpan; i++)
        DateTime(start.year, start.month + i),
    ];
    final peak = byMonth.values.fold<int>(0, (a, b) => a > b ? a : b);

    DateTime? busiest;
    for (final month in slots) {
      final ms = byMonth[month] ?? 0;
      if (ms > 0 && ms == peak) busiest = month;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final month in slots)
                Expanded(
                  child: _MonthBar(
                    month: month,
                    listenedMs: byMonth[month] ?? 0,
                    peak: peak,
                    height: _barHeight,
                    current: month.year == now.year && month.month == now.month,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            busiest == null
                ? 'Nothing heard in the last 12 months.'
                : 'Busiest: ${DateFormat.yMMMM().format(busiest)}, '
                      '${formatListeningTime(Duration(milliseconds: peak))}.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.listenedMs,
    required this.peak,
    required this.height,
    required this.current,
  });

  final DateTime month;
  final int listenedMs;
  final int peak;
  final double height;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final fraction = peak > 0 ? listenedMs / peak : 0.0;
    // A month with any listening at all stays visible above the baseline.
    final barHeight = listenedMs > 0
        ? (height * fraction).clamp(3.0, height)
        : 0.0;

    return Semantics(
      label: '${DateFormat.yMMMM().format(month)}: '
          '${formatListeningTime(Duration(milliseconds: listenedMs))}',
      excludeSemantics: true,
      child: Tooltip(
        message: '${DateFormat.yMMM().format(month)}\n'
            '${formatListeningTime(Duration(milliseconds: listenedMs))}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: current ? tokens.signal : tokens.signalDim,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Container(height: 1, color: tokens.hairline),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                DateFormat('MMMMM').format(month),
                style: type.panelLabel(size: 9).copyWith(
                  color: current ? tokens.signal : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent listens
// ---------------------------------------------------------------------------

/// One start of the track: when, how long, and how much of the recording
/// that covered. Amber when it fell short of the play threshold — measured
/// here in listening time, so at a fast speed the bar runs a little short of
/// what the player saw.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.track});

  final ListeningSessionEntry session;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final duration = track.durationMs;
    final fraction = duration > 0 ? session.listenedMs / duration : null;
    final short = duration > 0 &&
        session.listenedMs <
            scrobbleThresholdMs(Duration(milliseconds: duration));
    final heard = formatListeningTime(
      Duration(milliseconds: session.listenedMs),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat.yMMMd().add_jm().format(session.startedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth / 3,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      heard,
                      style: type
                          .instrument(11, weight: 500)
                          .copyWith(
                            color: short ? tokens.peak : scheme.onSurface,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          SignalRule(
            value: fraction,
            height: 3,
            color: short ? tokens.peak : tokens.signalDim,
            radius: 1.5,
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
