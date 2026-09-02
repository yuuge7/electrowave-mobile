import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../features/player/providers/accent_providers.dart';
import '../../features/player/providers/player_providers.dart';
import '../utils/format.dart';
import 'art_thumb.dart';
import 'deck.dart';

/// The docked transport.
///
/// Position lives in the rule across the top — the same element the seek bar
/// and the navigation marker use — rather than in a separate progress widget,
/// and it takes its colour from the cover that is playing.
///
/// Swipes do what they do on every player: sideways to change track, up to
/// open the full screen. Tapping still works; the gestures are there because
/// reaching a 40dp icon one-handed is the worst part of a docked bar.
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
    final tokens = context.deck;
    final accent =
        ref.watch(currentAccentProvider)?.resolve(scheme) ?? tokens.signal;
    final controller = ref.read(playerControllerProvider.notifier);

    return Material(
      color: scheme.surfaceContainer,
      child: Semantics(
        container: true,
        button: true,
        label: 'Now playing: ${current.title} by ${current.artist}. '
            'Open the player.',
        child: GestureDetector(
          onTap: () => context.push('/now-playing'),
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -180) {
              context.push('/now-playing');
            }
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 220) return;
            HapticFeedback.selectionClick();
            velocity < 0 ? controller.next() : controller.previous();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.hairline)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Playback position',
                  value: '${formatDuration(position)} of '
                      '${formatDuration(duration)}',
                  child: SignalRule(value: progress, color: accent),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'now-playing-art',
                        child: ArtThumb(
                          artPath: current.albumArtPath,
                          size: 42,
                          borderRadius: 6,
                          seed: current.album.isNotEmpty
                              ? current.album
                              : current.title,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              current.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              current.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      _TransportButton(
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        tooltip: playing ? 'Pause' : 'Play',
                        // The rule above takes the cover's colour; the
                        // controls stay the instrument's.
                        color: tokens.signal,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          controller.togglePlayPause();
                        },
                      ),
                      _TransportButton(
                        icon: Icons.skip_next_rounded,
                        tooltip: 'Next track',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          controller.next();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 26),
      tooltip: tooltip,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}
