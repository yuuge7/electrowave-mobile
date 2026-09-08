import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart' as type;
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../player/providers/player_providers.dart';
import '../providers/year_review_providers.dart';
import '../widgets/listening_heatmap.dart';

class YearReviewScreen extends ConsumerStatefulWidget {
  const YearReviewScreen({super.key, required this.year});

  final int year;

  @override
  ConsumerState<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends ConsumerState<YearReviewScreen> {
  final _cardKey = GlobalKey();
  late int _year = widget.year;
  bool _sharing = false;

  /// The calendar cell whose figures are open below the grid. Null until a
  /// day is tapped — the year's own totals are what the page is about, and a
  /// day panel that is always there would claim otherwise.
  DateTime? _selectedDay;

  /// Captures the card exactly as drawn on screen. The widget has to be in the
  /// tree and painted for this to work, which is why the card is the first
  /// thing on the page rather than something built off-screen on demand.
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'electrowave-$_year.png'));
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'My $_year in music — Electrowave',
        ),
      );
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not share: $error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(listenedYearsProvider);
    final shape = ref.watch(yearShapeProvider(_year));
    final listenedMs = ref.watch(yearListenedMsProvider(_year)).value ?? 0;
    final distinctTracks =
        ref.watch(yearDistinctTracksProvider(_year)).value ?? 0;
    final topTracks = ref.watch(yearTopTracksProvider(_year)).value ?? const [];
    final topArtists =
        ref.watch(yearTopArtistsProvider(_year)).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Year in review'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _year,
              items: [
                for (final year in years)
                  DropdownMenuItem(value: year, child: Text('$year')),
              ],
              onChanged: (year) => year == null
                  ? null
                  : setState(() {
                      _year = year;
                      // The open day belongs to the year that was showing.
                      _selectedDay = null;
                    }),
            ),
          ),
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            tooltip: 'Share card',
            onPressed: _sharing ? null : _share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: _cardKey,
              // The card is a fixed piece of artwork that gets exported as an
              // image: at a large accessibility text scale its type ran past
              // the edge, and the shared PNG would differ per phone.
              child: MediaQuery.withNoTextScaling(
                child: _ShareCard(
                  year: _year,
                  listenedMs: listenedMs,
                  distinctTracks: distinctTracks,
                  shape: shape,
                  topTrack: topTracks.isEmpty ? null : topTracks.first,
                  topArtist: topArtists.isEmpty ? null : topArtists.first,
                ),
              ),
            ),
          ),
          _sectionHeader(context, 'Listening calendar'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ListeningHeatmap(
              year: _year,
              byDay: shape.byDay,
              // Larger than the share card's grid: these squares are targets
              // here, not decoration.
              cellSize: 16,
              selectedDay: _selectedDay,
              onDayTap: (day) => setState(
                () => _selectedDay = _selectedDay == day ? null : day,
              ),
            ),
          ),
          if (!shape.isEmpty && _selectedDay == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Tap a day for what you played on it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_selectedDay != null)
            _DayPanel(
              day: _selectedDay!,
              year: _year,
              onChange: (day) => setState(() => _selectedDay = day),
              onClose: () => setState(() => _selectedDay = null),
            ),
          if (shape.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Nothing played this year yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (topTracks.isNotEmpty) ...[
            _sectionHeader(context, 'Most listened tracks'),
            for (final (index, stat) in topTracks.indexed)
              ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      SizedBox(width: 24, child: Text('${index + 1}')),
                      ArtThumb(
                        artPath: stat.track.albumArtPath,
                        size: 44,
                        seed: stat.track.album.isNotEmpty
                            ? stat.track.album
                            : stat.track.title,
                      ),
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
                      [for (final s in topTracks) s.track],
                      '$_year in review',
                    ),
              ),
          ],
          if (topArtists.isNotEmpty) ...[
            _sectionHeader(context, 'Most played artists'),
            for (final (index, stat) in topArtists.indexed)
              ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      SizedBox(width: 24, child: Text('${index + 1}')),
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
                trailing: Text('${stat.playCount} plays'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One day out of the calendar
// ---------------------------------------------------------------------------

/// What a single square on the calendar is made of.
///
/// The grid could always say *how much* — it is shaded by it — and never
/// *what*, which is the question anyone actually has when they spot a dark
/// day in March. It opens in place rather than as a modal sheet so the cell
/// it came from stays visible above it, and the arrows walk the year a day at
/// a time, which is the cheap way to recover from missing a 16dp target.
class _DayPanel extends ConsumerWidget {
  const _DayPanel({
    required this.day,
    required this.year,
    required this.onChange,
    required this.onClose,
  });

  final DateTime day;
  final int year;
  final ValueChanged<DateTime> onChange;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.deck;
    final listenedMs = ref.watch(dayListenedMsProvider(day)).value ?? 0;
    final plays = ref.watch(dayPlayCountProvider(day)).value ?? 0;
    final tracks = ref.watch(dayDistinctTracksProvider(day)).value ?? 0;
    final top = ref.watch(dayTopTracksProvider(day)).value ?? const [];
    final quiet = listenedMs == 0 && plays == 0;

    // The panel is anchored to the grid above it, so stepping stays inside
    // the year the grid is showing.
    final previous = DateTime(day.year, day.month, day.day - 1);
    final next = DateTime(day.year, day.month, day.day + 1);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 12, 6, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.hairline),
        color: scheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: PanelLabel(DateFormat.MMMEd().format(day)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous day',
                visualDensity: VisualDensity.compact,
                onPressed:
                    previous.year == year ? () => onChange(previous) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next day',
                visualDensity: VisualDensity.compact,
                onPressed: next.year == year ? () => onChange(next) : null,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close day',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatListeningTime(Duration(milliseconds: listenedMs)),
                style: type.counter(32).copyWith(
                  color: quiet ? scheme.onSurfaceVariant : tokens.signal,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const PanelLabel('Actually heard'),
          const SizedBox(height: 14),
          Divider(color: tokens.hairline, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DayFigure(
                  value: '$plays',
                  label: plays == 1 ? 'play' : 'plays',
                ),
              ),
              Expanded(
                child: _DayFigure(
                  value: '$tracks',
                  label: tracks == 1 ? 'track' : 'tracks',
                ),
              ),
            ],
          ),
          if (quiet)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 12, 0),
              child: Text(
                'Nothing played on this day.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else if (top.isNotEmpty) ...[
            const SizedBox(height: 16),
            const PanelLabel('Most heard'),
            const SizedBox(height: 4),
            for (final stat in top.take(5))
              _DayTrackRow(
                stat: stat,
                onTap: () =>
                    ref.read(playerControllerProvider.notifier).playFromList(
                      stat.track,
                      [for (final s in top) s.track],
                      DateFormat.yMMMd().format(day),
                    ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One of the two counts under the day's headline figure.
class _DayFigure extends StatelessWidget {
  const _DayFigure({required this.value, required this.label});

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

/// A track from the selected day, tappable to play the day back.
class _DayTrackRow extends StatelessWidget {
  const _DayTrackRow({required this.stat, required this.onTap});

  final TrackListeningStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              ArtThumb(
                artPath: stat.track.albumArtPath,
                size: 34,
                borderRadius: 6,
                seed: stat.track.album.isNotEmpty
                    ? stat.track.album
                    : stat.track.title,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stat.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      stat.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // A duration is a number and cannot ellipsize, so at a large
              // text scale it would push the title out of the row instead of
              // giving way itself.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth / 3,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatListeningTime(
                      Duration(milliseconds: stat.listenedMs),
                    ),
                    style: type
                        .instrument(11, weight: 500)
                        .copyWith(color: scheme.onSurface),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bit that gets rendered to a PNG. Self-contained colours rather than
/// theme lookups, so a shared card looks the same whoever opens it.
class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.year,
    required this.listenedMs,
    required this.distinctTracks,
    required this.shape,
    this.topTrack,
    this.topArtist,
  });

  final int year;
  final int listenedMs;
  final int distinctTracks;
  final ListeningYearShape shape;
  final TrackListeningStat? topTrack;
  final TopArtistStat? topArtist;

  static const _ink = Color(0xFF0D1B1E);
  static const _accent = Color(0xFF00E5CC);

  @override
  Widget build(BuildContext context) {
    final hours = Duration(milliseconds: listenedMs).inMinutes / 60;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10262B), _ink],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ELECTROWAVE',
                style: TextStyle(
                  color: _accent,
                  fontSize: 12,
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$year',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            hours >= 10 ? '${hours.round()}' : hours.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'hours listened',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Stat(value: '$distinctTracks', label: 'tracks'),
              _Stat(value: '${shape.activeDays}', label: 'active days'),
              _Stat(value: '${shape.longestStreak}', label: 'day streak'),
            ],
          ),
          const SizedBox(height: 20),
          if (topTrack != null)
            _TopLine(
              caption: 'Most listened',
              value: topTrack!.track.title,
              detail: topTrack!.track.artist,
            ),
          if (topArtist != null) ...[
            const SizedBox(height: 12),
            _TopLine(
              caption: 'Top artist',
              value: topArtist!.artist,
              detail: '${topArtist!.playCount} plays',
            ),
          ],
          if (shape.busiestDay != null) ...[
            const SizedBox(height: 12),
            _TopLine(
              caption: 'Busiest day',
              value: DateFormat.yMMMMd().format(shape.busiestDay!),
              detail: formatListeningTime(
                Duration(milliseconds: shape.busiestDayMs),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Same grid as the screen, shrunk to fit the card width.
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: _accent,
                surfaceContainerHighest: Color(0xFF1C3238),
              ),
            ),
            child: ListeningHeatmap(
              year: year,
              byDay: shape.byDay,
              cellSize: 4,
              gap: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TopLine extends StatelessWidget {
  const _TopLine({
    required this.caption,
    required this.value,
    required this.detail,
  });

  final String caption;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF00E5CC),
            fontSize: 10,
            letterSpacing: 2,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}
