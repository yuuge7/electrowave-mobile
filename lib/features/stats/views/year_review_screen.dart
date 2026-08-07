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
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
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
              onChanged: (year) =>
                  year == null ? null : setState(() => _year = year),
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
          _sectionHeader(context, 'Listening calendar'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ListeningHeatmap(year: _year, byDay: shape.byDay),
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
