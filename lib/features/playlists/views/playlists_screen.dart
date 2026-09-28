import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
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

  Widget _playlistTile(
    BuildContext context,
    WidgetRef ref,
    PlaylistWithCount entry,
  ) {
    final playlist = entry.playlist;
    final pinned = playlist.pinnedAt != null;
    return ListTile(
      leading: GeneratedTile(seed: playlist.name),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.trackCount} track${entry.trackCount == 1 ? '' : 's'}',
      ),
      onTap: () => context.go('/playlists/${playlist.id}'),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          final db = ref.read(databaseProvider);
          switch (action) {
            case 'add':
              context.push('/playlists/${playlist.id}/add');
            case 'rename':
              final name = await promptForText(
                context,
                title: 'Rename playlist',
                initial: playlist.name,
              );
              if (name != null && name.trim().isNotEmpty) {
                await db.renamePlaylist(playlist.id, name.trim());
              }
            case 'pin':
              await db.setPlaylistPinned(playlist.id, pinned: !pinned);
            case 'delete':
              final confirmed = await _confirmDelete(context, playlist.name);
              if (confirmed) await db.deletePlaylist(playlist.id);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'add', child: Text('Add tracks')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(
            value: 'pin',
            child: Text(pinned ? 'Unpin' : 'Pin to top'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Widget _smartTile(BuildContext context, WidgetRef ref, SmartPlaylist smart) {
    final definition = SmartPlaylistDefinition.decode(smart.rulesJson);
    final pinned = smart.pinnedAt != null;
    return ListTile(
      leading: GeneratedTile(seed: smart.name, icon: Icons.auto_awesome),
      title: Text(smart.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
            case 'pin':
              await db.setSmartPlaylistPinned(smart.id, pinned: !pinned);
            case 'delete':
              final confirmed = await _confirmDelete(context, smart.name);
              if (confirmed) await db.deleteSmartPlaylist(smart.id);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit rules')),
          PopupMenuItem(
            value: 'pin',
            child: Text(pinned ? 'Unpin' : 'Pin to top'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final smartPlaylists = ref.watch(smartPlaylistsProvider).value ?? const [];
    final pinned = ref.watch(pinnedPlaylistsProvider);

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
          // fill by hand, one the library keeps filled. Pinned lists of
          // either kind are lifted into their own run above both, so each
          // playlist still appears exactly once.
          final manual = [
            for (final entry in playlists)
              if (entry.playlist.pinnedAt == null) entry,
          ];
          final smart = [
            for (final playlist in smartPlaylists)
              if (playlist.pinnedAt == null) playlist,
          ];
          final rows = <_Row>[
            if (pinned.isNotEmpty) ...[
              _HeaderRow('Pinned', pinned.length),
              for (final item in pinned)
                switch (item) {
                  PinnedManualPlaylist(:final entry) => _PlaylistRow(entry),
                  PinnedSmartPlaylist(:final playlist) => _SmartRow(playlist),
                },
            ],
            if (manual.isNotEmpty) ...[
              _HeaderRow('Playlists', manual.length),
              for (final entry in manual) _PlaylistRow(entry),
            ],
            if (smart.isNotEmpty) ...[
              _HeaderRow('Smart lists · kept live', smart.length),
              for (final playlist in smart) _SmartRow(playlist),
            ],
          ];

          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              _HeaderRow(:final label, :final count) => SectionHeader(
                label,
                // The first header sits under the app bar, not another list.
                padding: index == 0
                    ? const EdgeInsets.fromLTRB(20, 8, 20, 4)
                    : const EdgeInsets.fromLTRB(20, 22, 20, 8),
                trailing: PanelLabel('$count'),
              ),
              _PlaylistRow(:final entry) => _playlistTile(context, ref, entry),
              _SmartRow(:final playlist) => _smartTile(context, ref, playlist),
            },
          );
        },
      ),
    );
  }
}

sealed class _Row {
  const _Row();
}

final class _HeaderRow extends _Row {
  const _HeaderRow(this.label, this.count);

  final String label;
  final int count;
}

final class _PlaylistRow extends _Row {
  const _PlaylistRow(this.entry);

  final PlaylistWithCount entry;
}

final class _SmartRow extends _Row {
  const _SmartRow(this.playlist);

  final SmartPlaylist playlist;
}
