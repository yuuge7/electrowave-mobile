import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/services/local_log.dart';
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
  final writer = ref.read(tagWriterProvider);
  final message = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BulkTagEditor(tracks: tracks, writer: writer),
  );
  if (message != null && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BulkTagEditor extends StatefulWidget {
  const _BulkTagEditor({required this.tracks, required this.writer});
  final List<Track> tracks;
  final TagWriter writer;

  @override
  State<_BulkTagEditor> createState() => _BulkTagEditorState();
}

class _BulkTagEditorState extends State<_BulkTagEditor> {
  final _artist = TextEditingController(),
      _album = TextEditingController(),
      _genre = TextEditingController(),
      _year = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  int _processed = 0;

  @override
  void dispose() {
    for (final c in [_artist, _album, _genre, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    String? value(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final edit = TagEdit(
      artist: value(_artist),
      album: value(_album),
      genre: value(_genre),
      year: int.tryParse(_year.text.trim()),
    );
    if (edit.artist == null &&
        edit.album == null &&
        edit.genre == null &&
        edit.year == null) {
      Navigator.pop(context, 'No tags changed');
      return;
    }
    setState(() => _saving = true);
    final writer = widget.writer;
    final tracks = widget.tracks;
    var failed = 0;
    for (final track in tracks) {
      try {
        if (await writer.apply(track, edit) != null) failed++;
      } catch (e, s) {
        LocalLog.record(e, s);
        failed++;
      }
      if (mounted) setState(() => _processed++);
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      failed == 0
          ? 'Tags updated'
          : '$failed of ${tracks.length} tracks could not be fully written',
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Edit ${widget.tracks.length} tracks'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Blank fields stay unchanged. Saving writes these tags to your music files.',
              ),
              TextFormField(
                enabled: !_saving,
                controller: _artist,
                decoration: const InputDecoration(labelText: 'Artist'),
              ),
              TextFormField(
                enabled: !_saving,
                controller: _album,
                decoration: const InputDecoration(labelText: 'Album'),
              ),
              TextFormField(
                enabled: !_saving,
                controller: _genre,
                decoration: const InputDecoration(labelText: 'Genre'),
              ),
              TextFormField(
                enabled: !_saving,
                controller: _year,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final y = int.tryParse(v.trim());
                  return y != null && y > 0 && y <= 9999
                      ? null
                      : 'Enter a year from 1 to 9999';
                },
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year'),
              ),
              if (_saving) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _processed / widget.tracks.length,
                ),
                Text('Saved $_processed/${widget.tracks.length}'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save tags'),
        ),
      ],
    ),
  );
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
            final selection = ref.read(librarySelectionProvider.notifier);
            final db = ref.read(databaseProvider);
            final player = ref.read(playerControllerProvider.notifier);
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
                  await db.softDeleteTrack(t.id);
                  player.removeTrackFromQueues(t.id);
                }
            }
            selection.state = {};
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
