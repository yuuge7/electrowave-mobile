import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/track_context_menu.dart' show promptForText;
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../../shared/widgets/state_views.dart';
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
  Future<void> _createPlaylist(BuildContext context) async {
    final smart = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('New playlist'),
            subtitle: const Text('Pick the tracks yourself'),
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
    );
    if (smart == null || !context.mounted) return;

    context.push(smart ? '/playlists/smart/new' : '/playlists/new');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final smartPlaylists = ref.watch(smartPlaylistsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: Builder(
        builder: (context) {
          final signal = context.deck.signal;
          return FloatingActionButton(
            tooltip: 'New playlist',
            backgroundColor: Color.alphaBlend(
              signal.withValues(alpha: 0.16),
              Theme.of(context).colorScheme.surface,
            ),
            foregroundColor: signal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: signal.withValues(alpha: 0.55), width: 1.5),
            ),
            onPressed: () => _createPlaylist(context),
            child: const Icon(Icons.add),
          );
        },
      ),
      body: AsyncView(
        value: playlistsAsync,
        data: (playlists) {
          if (playlists.isEmpty && smartPlaylists.isEmpty) {
            return EmptyStateView(
              icon: Icons.queue_music_outlined,
              title: 'No playlists yet',
              message: 'Build one by hand, or write rules and let the library '
                  'keep it filled in for you.',
              action: FilledButton.icon(
                onPressed: () => _createPlaylist(context),
                icon: const Icon(Icons.add),
                label: const Text('New playlist'),
              ),
            );
          }
          // Two kinds of list live here and they behave differently: one you
          // fill by hand, one the library keeps filled. Concatenating them
          // into a single run with index arithmetic hid that entirely.
          const manualHeader = 1;
          final smartHeader = smartPlaylists.isEmpty ? 0 : 1;
          final manualCount = playlists.length;

          return ListView.builder(
            itemCount: manualHeader +
                manualCount +
                smartHeader +
                smartPlaylists.length,
            itemBuilder: (context, rawIndex) {
              if (rawIndex == 0) {
                return SectionHeader(
                  'Playlists',
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  trailing: PanelLabel('$manualCount'),
                );
              }
              if (rawIndex == manualHeader + manualCount &&
                  smartPlaylists.isNotEmpty) {
                return SectionHeader(
                  'Smart lists · kept live',
                  trailing: PanelLabel('${smartPlaylists.length}'),
                );
              }
              final index = rawIndex > manualHeader + manualCount
                  ? rawIndex - manualHeader - smartHeader
                  : rawIndex - manualHeader;
              if (index >= playlists.length) {
                final smart = smartPlaylists[index - playlists.length];
                final definition = SmartPlaylistDefinition.decode(
                  smart.rulesJson,
                );
                return ListTile(
                  leading: GeneratedTile(
                    seed: smart.name,
                    icon: Icons.auto_awesome,
                  ),
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
                leading: GeneratedTile(seed: entry.playlist.name),
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
                      case 'add':
                        context.push('/playlists/${entry.playlist.id}/add');
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
                    PopupMenuItem(value: 'add', child: Text('Add tracks')),
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
