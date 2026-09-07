import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../../player/providers/player_providers.dart';
import '../providers/playlist_providers.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(playlistId)).value;
    final tracksAsync = ref.watch(playlistTracksProvider(playlistId));
    final controller = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Add tracks',
            onPressed: () => context.push('/playlists/$playlistId/add'),
          ),
          tracksAsync.maybeWhen(
            data: (tracks) => tracks.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.play_arrow),
                    tooltip: 'Play all',
                    onPressed: () => controller.playFromList(
                      tracks.first,
                      tracks,
                      playlist?.name ?? 'Playlist',
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: AsyncView<List<Track>>(
        value: tracksAsync,
        data: (tracks) {
          if (tracks.isEmpty) {
            return EmptyStateView(
              icon: Icons.playlist_add,
              title: 'Empty playlist',
              message: 'Pick tracks from your library — search, take whole '
                  'albums, or hold to grab a run of them at once.',
              action: FilledButton.icon(
                onPressed: () => context.push('/playlists/$playlistId/add'),
                icon: const Icon(Icons.add),
                label: const Text('Add tracks'),
              ),
              secondaryAction: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'One at a time still works: long-press any track in the '
                  'library, then Add to playlist.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ReorderableListView.builder(
            itemCount: tracks.length,
            onReorderItem: (oldIndex, newIndex) {
              final ids = [for (final t in tracks) t.id];
              final moved = ids.removeAt(oldIndex);
              ids.insert(newIndex, moved);
              ref.read(databaseProvider).reorderPlaylist(playlistId, ids);
            },
            itemBuilder: (context, index) {
              final track = tracks[index];
              return ListTile(
                key: ValueKey(track.id),
                onTap: () => controller.playFromList(
                  track,
                  tracks,
                  playlist?.name ?? 'Playlist',
                ),
                onLongPress: () => showTrackContextMenu(context, track),
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
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove from playlist',
                      onPressed: () => ref
                          .read(databaseProvider)
                          .removeTrackFromPlaylist(playlistId, track.id),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
