import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/track_context_menu.dart' show promptForText;
import '../models/smart_playlist.dart';
import '../providers/playlist_providers.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('"$name" will be deleted. Tracks stay in your library.'),
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
    return confirmed == true;
  }

  /// The + button covers both kinds, so it asks which one first.
  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final smart = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('New playlist'),
              subtitle: const Text('Tracks you add by hand'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('New smart playlist'),
              subtitle: const Text(
                'Rules the library fills in for you, kept live',
              ),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (smart == null || !context.mounted) return;

    if (smart) {
      context.push('/playlists/smart/new');
      return;
    }
    final name = await promptForText(
      context,
      title: 'New playlist',
      hint: 'Playlist name',
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(databaseProvider).createPlaylist(name.trim());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final smartPlaylists = ref.watch(smartPlaylistsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New playlist',
        onPressed: () => _createPlaylist(context, ref),
        child: const Icon(Icons.add),
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (playlists) {
          if (playlists.isEmpty && smartPlaylists.isEmpty) {
            return const Center(
              child: Text('No playlists yet — tap + to create one'),
            );
          }
          return ListView.builder(
            itemCount: playlists.length + smartPlaylists.length,
            itemBuilder: (context, index) {
              if (index >= playlists.length) {
                final smart = smartPlaylists[index - playlists.length];
                final definition = SmartPlaylistDefinition.decode(
                  smart.rulesJson,
                );
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.auto_awesome)),
                  title: Text(
                    smart.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    definition.describe(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.go('/playlists/smart/${smart.id}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      final db = ref.read(databaseProvider);
                      switch (action) {
                        case 'edit':
                          context.push('/playlists/smart/${smart.id}/edit');
                        case 'delete':
                          final confirmed = await _confirmDelete(
                            context,
                            smart.name,
                          );
                          if (confirmed) await db.deleteSmartPlaylist(smart.id);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit rules')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              }
              final entry = playlists[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    entry.playlist.name.isNotEmpty
                        ? entry.playlist.name[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(
                  entry.playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${entry.trackCount} track${entry.trackCount == 1 ? '' : 's'}',
                ),
                onTap: () => context.go('/playlists/${entry.playlist.id}'),
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
                            entry.playlist.id,
                            name.trim(),
                          );
                        }
                      case 'delete':
                        final confirmed = await _confirmDelete(
                          context,
                          entry.playlist.name,
                        );
                        if (confirmed) {
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
