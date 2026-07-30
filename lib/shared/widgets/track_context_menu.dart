import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../features/player/providers/player_providers.dart';
import '../../features/playlists/providers/playlist_providers.dart';
import 'art_thumb.dart';

Future<void> showTrackContextMenu(BuildContext context, Track track) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _TrackMenuSheet(track: track),
  );
}

class _TrackMenuSheet extends ConsumerWidget {
  const _TrackMenuSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ArtThumb(artPath: track.albumArtPath),
            title: Text(track.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(track.artist,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text('Play next'),
            onTap: () {
              controller.playNextInQueue(track);
              Navigator.pop(context);
              _toast(context, 'Playing next: ${track.title}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Add to queue'),
            onTap: () {
              controller.addToQueue(track);
              Navigator.pop(context);
              _toast(context, 'Added to queue: ${track.title}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Add to playlist'),
            onTap: () async {
              Navigator.pop(context);
              await _showAddToPlaylist(context, ref, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove from library'),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(databaseProvider).softDeleteTrack(track.id);
              controller.removeTrackFromQueues(track.id);
              if (context.mounted) {
                _toast(context, 'Removed from library: ${track.title}');
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _showAddToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return Consumer(
        builder: (context, ref, _) {
          final playlists = ref.watch(playlistsProvider).value ?? [];
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New playlist'),
                  onTap: () async {
                    final navigator = Navigator.of(sheetContext);
                    final name = await promptForText(
                      context,
                      title: 'New playlist',
                      hint: 'Playlist name',
                    );
                    if (name == null || name.trim().isEmpty) return;
                    final db = ref.read(databaseProvider);
                    final id = await db.createPlaylist(name.trim());
                    await db.addTrackToPlaylist(id, track.id);
                    navigator.pop();
                  },
                ),
                for (final entry in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(entry.playlist.name),
                    subtitle: Text('${entry.trackCount} tracks'),
                    onTap: () async {
                      final navigator = Navigator.of(sheetContext);
                      await ref
                          .read(databaseProvider)
                          .addTrackToPlaylist(entry.playlist.id, track.id);
                      navigator.pop();
                    },
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Small shared text-input dialog (new playlist, rename, custom minutes...).
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  TextInputType keyboardType = TextInputType.text,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
