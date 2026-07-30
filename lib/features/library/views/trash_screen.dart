import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../providers/browse_providers.dart';

/// Removing a track from the library is a soft delete so play history and
/// stats survive. This screen makes those rows reachable again — restore them,
/// or purge them for good. Audio files on disk are never touched.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmEmpty(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
            'These tracks will be removed from the library for good, along '
            'with their play history and playlist entries. The audio files on '
            'your device are not deleted.'),
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
    if (confirmed != true) return;

    final count = await ref.read(databaseProvider).emptyTrash();
    if (context.mounted) {
      _toast(context, 'Removed $count track${count == 1 ? '' : 's'}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleted = ref.watch(deletedTracksProvider);
    final db = ref.read(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Removed tracks'),
        actions: [
          if ((deleted.value ?? const []).isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Delete all permanently',
              onPressed: () => _confirmEmpty(context, ref),
            ),
        ],
      ),
      body: deleted.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing here. Tracks you remove from the library show up '
                  'in this list so you can put them back.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return ListTile(
                leading: ArtThumb(artPath: track.albumArtPath),
                title: Text(track.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${track.artist} · ${track.album}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore_from_trash),
                      tooltip: 'Restore',
                      onPressed: () async {
                        await db.restoreTrack(track.id);
                        if (context.mounted) {
                          _toast(context, 'Restored ${track.title}');
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever),
                      tooltip: 'Delete permanently',
                      onPressed: () => db.purgeTrack(track.id),
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
