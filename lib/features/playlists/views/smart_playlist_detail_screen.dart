import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../../player/providers/player_providers.dart';
import '../providers/playlist_providers.dart';

class SmartPlaylistDetailScreen extends ConsumerWidget {
  const SmartPlaylistDetailScreen({super.key, required this.smartPlaylistId});

  final int smartPlaylistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(smartPlaylistProvider(smartPlaylistId)).value;
    final definition = ref.watch(
      smartPlaylistDefinitionProvider(smartPlaylistId),
    );
    final tracksAsync = ref.watch(smartPlaylistTracksProvider(smartPlaylistId));
    final controller = ref.read(playerControllerProvider.notifier);
    final name = playlist?.name ?? 'Smart playlist';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          tracksAsync.maybeWhen(
            data: (tracks) => tracks.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        tooltip: 'Play all',
                        onPressed: () =>
                            controller.playFromList(tracks.first, tracks, name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        tooltip: 'Shuffle',
                        onPressed: () =>
                            controller.shufflePlayList(tracks, name),
                      ),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'edit':
                  context.push('/playlists/smart/$smartPlaylistId/edit');
                case 'delete':
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete smart playlist?'),
                      content: Text(
                        '"$name" will be deleted. '
                        'Tracks stay in your library.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref
                        .read(databaseProvider)
                        .deleteSmartPlaylist(smartPlaylistId);
                    if (context.mounted) context.go('/playlists');
                  }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit rules')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nothing matches these rules yet.\n\n'
                  '${definition?.describe() ?? ''}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              if (definition != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          definition.describe(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      onTap: () => controller.playFromList(track, tracks, name),
                      onLongPress: () => showTrackContextMenu(context, track),
                      leading: ArtThumb(artPath: track.albumArtPath),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
