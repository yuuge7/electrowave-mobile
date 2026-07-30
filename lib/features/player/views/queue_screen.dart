import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
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
                leading: ArtThumb(artPath: state.current!.albumArtPath),
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
                    leading: ArtThumb(artPath: track.albumArtPath),
                    title: Text(track.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove from queue',
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
                  leading: ArtThumb(artPath: track.albumArtPath),
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
              child: Center(child: Text('Queue is empty')),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ),
    );
  }
}
