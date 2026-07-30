import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../providers/library_providers.dart';
import '../services/tag_writer.dart';

Future<void> showTagEditor(BuildContext context, Track track) {
  return showDialog(
    context: context,
    builder: (dialogContext) => _TagEditorDialog(track: track),
  );
}

class _TagEditorDialog extends ConsumerStatefulWidget {
  const _TagEditorDialog({required this.track});

  final Track track;

  @override
  ConsumerState<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends ConsumerState<_TagEditorDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.track.title);
  late final TextEditingController _artist =
      TextEditingController(text: widget.track.artist);
  late final TextEditingController _album =
      TextEditingController(text: widget.track.album);
  late final TextEditingController _genre =
      TextEditingController(text: widget.track.genre ?? '');
  late final TextEditingController _trackNumber = TextEditingController(
      text: widget.track.trackNumber?.toString() ?? '');
  late final TextEditingController _discNumber =
      TextEditingController(text: widget.track.discNumber?.toString() ?? '');
  late final TextEditingController _year =
      TextEditingController(text: widget.track.year?.toString() ?? '');

  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    _trackNumber.dispose();
    _discNumber.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Title can’t be empty')));
      return;
    }

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final edit = TagEdit(
      title: _title.text.trim(),
      artist: _artist.text.trim().isEmpty
          ? 'Unknown artist'
          : _artist.text.trim(),
      album:
          _album.text.trim().isEmpty ? 'Unknown album' : _album.text.trim(),
      genre: _genre.text.trim(),
      trackNumber: int.tryParse(_trackNumber.text.trim()),
      discNumber: int.tryParse(_discNumber.text.trim()),
      year: int.tryParse(_year.text.trim()),
    );

    final error = await ref.read(tagWriterProvider).apply(widget.track, edit);

    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error ?? 'Tags updated')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit tags'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: _artist,
              decoration: const InputDecoration(labelText: 'Artist'),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: _album,
              decoration: const InputDecoration(labelText: 'Album'),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: _genre,
              decoration: const InputDecoration(labelText: 'Genre'),
              textCapitalization: TextCapitalization.words,
            ),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: TextField(
                    controller: _trackNumber,
                    decoration: const InputDecoration(labelText: 'Track #'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _discNumber,
                    decoration: const InputDecoration(labelText: 'Disc #'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _year,
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
