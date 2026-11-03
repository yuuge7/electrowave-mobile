import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../../player/providers/player_providers.dart';
import '../providers/library_providers.dart';
import '../services/tag_writer.dart';

Future<void> addManyToPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final db = ref.read(databaseProvider);
  final lists = await db.watchPlaylists().first;
  if (!context.mounted) return;
  final choice = await showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Add to playlist'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, -1),
          child: const Text('New playlist'),
        ),
        for (final list in lists)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, list.playlist.id),
            child: Text(list.playlist.name),
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  var id = choice;
  if (choice == -1) {
    final name = await promptForText(
      context,
      title: 'New playlist',
      hint: 'Playlist name',
    );
    if (name == null || name.trim().isEmpty) return;
    id = await db.createPlaylist(name.trim());
  }
  await db.addTracksToPlaylist(id, tracks.map((t) => t.id).toList());
}

Future<void> editManyTags(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final artist = TextEditingController(),
      album = TextEditingController(),
      genre = TextEditingController(),
      year = TextEditingController();
  final save = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Edit ${tracks.length} tracks'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Blank fields stay unchanged. Saving writes these tags to your music files.',
            ),
            TextField(
              controller: artist,
              decoration: const InputDecoration(labelText: 'Artist'),
            ),
            TextField(
              controller: album,
              decoration: const InputDecoration(labelText: 'Album'),
            ),
            TextField(
              controller: genre,
              decoration: const InputDecoration(labelText: 'Genre'),
            ),
            TextField(
              controller: year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Year'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Save tags'),
        ),
      ],
    ),
  );
  String? value(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();
  final edit = TagEdit(
    artist: value(artist),
    album: value(album),
    genre: value(genre),
    year: int.tryParse(year.text),
  );
  for (final c in [artist, album, genre, year]) {
    c.dispose();
  }
  if (save != true) return;
  var failed = 0;
  for (final track in tracks) {
    if (await ref.read(tagWriterProvider).apply(track, edit) != null) failed++;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Tags updated'
              : 'Library updated; $failed files could not be written',
        ),
      ),
    );
  }
}

class BulkActions extends ConsumerWidget {
  const BulkActions({super.key, required this.tracks});
  final List<Track> tracks;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(librarySelectionProvider);
    final selected = tracks.where((t) => ids.contains(t.id)).toList();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () =>
              ref.read(librarySelectionProvider.notifier).state = {},
          child: Text('${selected.length} selected · Cancel'),
        ),
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: () => ref.read(librarySelectionProvider.notifier).state =
              tracks.map((t) => t.id).toSet(),
        ),
        PopupMenuButton<String>(
          tooltip: 'Selection actions',
          onSelected: (action) async {
            switch (action) {
              case 'queue':
                ref
                    .read(playerControllerProvider.notifier)
                    .addManyToQueue(selected);
              case 'playlist':
                await addManyToPlaylist(context, ref, selected);
              case 'tags':
                await editManyTags(context, ref, selected);
              case 'remove':
                for (final t in selected) {
                  await ref.read(databaseProvider).softDeleteTrack(t.id);
                  ref
                      .read(playerControllerProvider.notifier)
                      .removeTrackFromQueues(t.id);
                }
            }
            ref.read(librarySelectionProvider.notifier).state = {};
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'queue', child: Text('Add to queue')),
            PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
            PopupMenuItem(value: 'tags', child: Text('Edit tags')),
            PopupMenuItem(value: 'remove', child: Text('Remove from library')),
          ],
        ),
      ],
    );
  }
}
