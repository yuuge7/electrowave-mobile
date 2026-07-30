import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/providers/player_providers.dart';
import 'art_thumb.dart';

/// Docked above the bottom navigation bar; taps expand to now-playing.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(playerControllerProvider.select((s) => s.current));
    if (current == null) return const SizedBox.shrink();

    final playing = ref.watch(playingProvider).value ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = current.durationMs > 0
        ? Duration(milliseconds: current.durationMs)
        : (ref.watch(durationProvider).value ?? Duration.zero);
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(playerControllerProvider.notifier);

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push('/now-playing'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  ArtThumb(artPath: current.albumArtPath, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(current.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: controller.togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: () => controller.next(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
