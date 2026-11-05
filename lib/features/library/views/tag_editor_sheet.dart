import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/services/local_log.dart';
import '../providers/library_providers.dart';
import '../services/tag_writer.dart';

Future<void> showTagEditor(BuildContext context, Track track) {
  return showDialog(
    context: context,
    barrierDismissible: false,
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
  late final TextEditingController _title = TextEditingController(
    text: widget.track.title,
  );
  late final TextEditingController _artist = TextEditingController(
    text: widget.track.artist,
  );
  late final TextEditingController _album = TextEditingController(
    text: widget.track.album,
  );
  late final TextEditingController _genre = TextEditingController(
    text: widget.track.genre ?? '',
  );
  late final TextEditingController _trackNumber = TextEditingController(
    text: widget.track.trackNumber?.toString() ?? '',
  );
  late final TextEditingController _discNumber = TextEditingController(
    text: widget.track.discNumber?.toString() ?? '',
  );
  late final TextEditingController _year = TextEditingController(
    text: widget.track.year?.toString() ?? '',
  );

  bool _saving = false;
  late double _rating = widget.track.rating.toDouble();
  late final _albumArtist = TextEditingController(
    text: widget.track.albumArtist ?? '',
  );

  @override
  void dispose() {
    _albumArtist.dispose();
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
      albumArtist: _albumArtist.text.trim(),
      title: _title.text.trim(),
      artist: _artist.text.trim().isEmpty
          ? kUnknownArtist
          : _artist.text.trim(),
      album: _album.text.trim().isEmpty ? 'Unknown album' : _album.text.trim(),
      genre: _genre.text.trim(),
      trackNumber: int.tryParse(_trackNumber.text.trim()),
      discNumber: int.tryParse(_discNumber.text.trim()),
      year: int.tryParse(_year.text.trim()),
    );

    final writer = ref.read(tagWriterProvider);
    final rating = _rating.round();
    try {
      var error = await writer.apply(widget.track, edit);
      if (rating != widget.track.rating) {
        error =
            await writer.apply(widget.track, TagEdit(rating: rating)) ?? error;
      }
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error ?? 'Tags updated')));
    } catch (e, s) {
      LocalLog.record(e, s);
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save tags. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Edit tags'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              TextField(
                controller: _albumArtist,
                decoration: const InputDecoration(labelText: 'Album artist'),
              ),
              Text('Rating: ${_rating.round()} / 5'),
              Slider(
                value: _rating,
                min: 0,
                max: 5,
                divisions: 5,
                label: '${_rating.round()} stars',
                onChanged: _saving ? null : (v) => setState(() => _rating = v),
              ),
              const Text(
                'Ratings write to MP3, FLAC and WAV tags. Other formats keep the rating in the library.',
              ),
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
      ),
    );
  }
}
