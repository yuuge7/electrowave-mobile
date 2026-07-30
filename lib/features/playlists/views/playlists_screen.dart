import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/track_context_menu.dart' show promptForText;
import '../providers/playlist_providers.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New playlist',
        onPressed: () async {
          final name = await promptForText(
            context,
            title: 'New playlist',
            hint: 'Playlist name',
          );
          if (name != null && name.trim().isNotEmpty) {
            await ref.read(databaseProvider).createPlaylist(name.trim());
          }
        },
        child: const Icon(Icons.add),
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (playlists) {
          if (playlists.isEmpty) {
            return const Center(
              child: Text('No playlists yet — tap + to create one'),
            );
          }
          return ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final entry = playlists[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(entry.playlist.name.isNotEmpty
                      ? entry.playlist.name[0].toUpperCase()
                      : '?'),
                ),
                title: Text(entry.playlist.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${entry.trackCount} track${entry.trackCount == 1 ? '' : 's'}'),
                onTap: () =>
                    context.go('/playlists/${entry.playlist.id}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    final db = ref.read(databaseProvider);
                    switch (action) {
                      case 'rename':
                        final name = await promptForText(
                          context,
                          title: 'Rename playlist',
                          initial: entry.playlist.name,
                        );
                        if (name != null && name.trim().isNotEmpty) {
                          await db.renamePlaylist(
                              entry.playlist.id, name.trim());
                        }
                      case 'delete':
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Delete playlist?'),
                            content: Text(
                                '"${entry.playlist.name}" will be deleted. '
                                'Tracks stay in your library.'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await db.deletePlaylist(entry.playlist.id);
                        }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
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
