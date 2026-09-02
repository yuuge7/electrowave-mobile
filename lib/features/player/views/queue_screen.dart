import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/player_providers.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final upcoming = state.upcomingContext;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Queue')),
      body: CustomScrollView(
        slivers: [
          if (state.current != null) ...[
            _header(context, 'Now playing'),
            SliverToBoxAdapter(
              child: ListTile(
                leading: ArtThumb(
                  artPath: state.current!.albumArtPath,
                  seed: state.current!.album.isNotEmpty
                      ? state.current!.album
                      : state.current!.title,
                ),
                title: Text(state.current!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w600)),
                subtitle: Text(state.current!.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing:
                    Text(formatDurationMs(state.current!.durationMs)),
              ),
            ),
          ],
          if (state.manualQueue.isNotEmpty) ...[
            _header(context, 'Next in queue · drag to reorder'),
            SliverReorderableList(
              itemCount: state.manualQueue.length,
              onReorderItem: controller.reorderManualQueue,
              itemBuilder: (context, index) {
                final track = state.manualQueue[index];
                return Material(
                  key: ValueKey('manual-$index-${track.id}'),
                  child: ListTile(
                    onTap: () => controller.playManualQueueItem(index),
                    leading: ArtThumb(
                      artPath: track.albumArtPath,
                      seed: track.album.isNotEmpty ? track.album : track.title,
                    ),
                    title: Text(track.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove ${track.title} from queue',
                          onPressed: () =>
                              controller.removeFromManualQueue(index),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            _header(
              context,
              'Up next · ${state.contextName.isEmpty ? 'Context' : state.contextName}',
            ),
            SliverList.builder(
              itemCount: upcoming.length,
              itemBuilder: (context, index) {
                final track = upcoming[index];
                return ListTile(
                  onTap: () => controller.playContextTrack(track),
                  leading: ArtThumb(
                      artPath: track.albumArtPath,
                      seed: track.album.isNotEmpty ? track.album : track.title,
                    ),
                  title: Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(track.artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(formatDurationMs(track.durationMs)),
                );
              },
            ),
          ],
          if (state.current == null &&
              state.manualQueue.isEmpty &&
              upcoming.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView(
                icon: Icons.queue_music_outlined,
                title: 'Queue is empty',
                message: 'Play a track and the list it came from becomes the '
                    'queue. Play next and Add to queue always jump ahead of '
                    'it.',
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // Region names are engraved panel labels, not accent-coloured text: the
  // accent means "this is what is playing", and a heading is not that.
  Widget _header(BuildContext context, String text) =>
      SliverToBoxAdapter(child: SectionHeader(text));
}
