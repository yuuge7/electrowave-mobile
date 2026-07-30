import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../../library/providers/browse_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/player_providers.dart';
import '../providers/sleep_timer_provider.dart';
import 'sleep_timer_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final playerTrack = state.current;
    final controller = ref.read(playerControllerProvider.notifier);

    if (playerTrack == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    // The player holds a snapshot; watch the row so favorite/tag edits show
    // up here immediately.
    final track =
        ref.watch(trackStreamProvider(playerTrack.id)).value ?? playerTrack;

    final playing = ref.watch(playingProvider).value ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final streamDuration =
        ref.watch(durationProvider).value ?? Duration.zero;
    final duration = streamDuration > Duration.zero
        ? streamDuration
        : Duration(milliseconds: track.durationMs);

    final sleepTimer = ref.watch(sleepTimerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text('PLAYING FROM',
                style: Theme.of(context).textTheme.labelSmall),
            Text(
              state.contextName.isEmpty ? 'Queue' : state.contextName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              track.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: track.isFavorite ? scheme.primary : null,
            ),
            tooltip: track.isFavorite ? 'Remove from favorites' : 'Favorite',
            onPressed: () => ref
                .read(databaseProvider)
                .setFavorite(track.id, !track.isFavorite),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showTrackContextMenu(context, track),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              // Large album art
              AspectRatio(
                aspectRatio: 1,
                child: ArtThumb(
                  artPath: track.albumArtPath,
                  size: double.infinity,
                  borderRadius: 16,
                  iconSize: 96,
                ),
              ),
              const Spacer(),
              // Title / artist
              Text(
                track.title,
                style: Theme.of(context).textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${track.artist}${track.album.isNotEmpty ? ' · ${track.album}' : ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (sleepTimer != null) ...[
                const SizedBox(height: 12),
                _SleepTimerChip(sleepTimer: sleepTimer),
              ],
              const SizedBox(height: 16),
              // Seek bar
              _SeekBar(
                position: position,
                duration: duration,
                onSeek: controller.seek,
              ),
              const SizedBox(height: 8),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: state.shuffle ? scheme.primary : null,
                    ),
                    tooltip: 'Shuffle',
                    onPressed: controller.toggleShuffle,
                  ),
                  IconButton(
                    iconSize: 42,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: controller.previous,
                  ),
                  IconButton.filled(
                    iconSize: 42,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: controller.togglePlayPause,
                  ),
                  IconButton(
                    iconSize: 42,
                    icon: const Icon(Icons.skip_next),
                    onPressed: () => controller.next(),
                  ),
                  IconButton(
                    icon: Icon(
                      state.repeat == RepeatMode.one
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: state.repeat != RepeatMode.off
                          ? scheme.primary
                          : null,
                    ),
                    tooltip: 'Repeat',
                    onPressed: controller.cycleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Secondary actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => showSleepTimerSheet(context),
                    icon: Icon(
                      Icons.bedtime_outlined,
                      size: 20,
                      color: sleepTimer != null ? scheme.primary : null,
                    ),
                    label: Text(
                      'Sleep timer',
                      style: TextStyle(
                          color: sleepTimer != null ? scheme.primary : null),
                    ),
                  ),
                  const _SpeedButton(),
                  TextButton.icon(
                    onPressed: () => context.push('/queue'),
                    icon: const Icon(Icons.queue_music, size: 20),
                    label: const Text('Queue'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Playback speed. Persisted, and re-applied to every track that loads.
class _SpeedButton extends ConsumerWidget {
  const _SpeedButton();

  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(
        settingsControllerProvider.select((settings) => settings.playbackRate));
    final scheme = Theme.of(context).colorScheme;
    final custom = rate != 1.0;

    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: rate,
      onSelected: (value) => ref
          .read(settingsControllerProvider.notifier)
          .setPlaybackRate(value),
      itemBuilder: (context) => [
        for (final value in _rates)
          PopupMenuItem(
            value: value,
            child: Text(value == 1.0 ? 'Normal (1×)' : '$value×'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed,
                size: 20, color: custom ? scheme.primary : null),
            const SizedBox(width: 4),
            Text(
              custom ? '$rate×' : 'Speed',
              style: TextStyle(color: custom ? scheme.primary : null),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepTimerChip extends ConsumerWidget {
  const _SleepTimerChip({required this.sleepTimer});

  final SleepTimerState sleepTimer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = sleepTimer.endOfTrack
        ? 'Sleep: end of track'
        : 'Sleep: ${formatDuration(sleepTimer.remaining)}';
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InputChip(
          avatar: const Icon(Icons.bedtime, size: 18),
          label: Text(label),
          onDeleted: () => ref.read(sleepTimerProvider.notifier).cancel(),
          deleteIcon: const Icon(Icons.close, size: 18),
          onPressed: () => showSleepTimerSheet(context),
        ),
        ActionChip(
          label: const Text('+15 min'),
          onPressed: () => ref.read(sleepTimerProvider.notifier).extend15(),
        ),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final valueMs = (_dragValue ??
            widget.position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Column(
      children: [
        Slider(
          value: maxMs > 0 ? valueMs : 0,
          max: maxMs > 0 ? maxMs : 1,
          onChanged: maxMs > 0
              ? (value) => setState(() => _dragValue = value)
              : null,
          onChangeEnd: maxMs > 0
              ? (value) {
                  widget.onSeek(Duration(milliseconds: value.round()));
                  setState(() => _dragValue = null);
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(
                  Duration(milliseconds: valueMs.round()))),
              Text(formatDuration(widget.duration)),
            ],
          ),
        ),
      ],
    );
  }
}
