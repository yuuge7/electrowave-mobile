import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/database/database.dart';

/// Edited tag values. A null field means "leave this tag alone".
class TagEdit {
  const TagEdit({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
}

/// Runs in a worker isolate: writing tags rewrites the file header and can
/// block for a noticeable moment on large files.
void _writeTags(({String path, TagEdit edit}) args) {
  final edit = args.edit;
  updateMetadata(File(args.path), (metadata) {
    if (edit.title != null) metadata.setTitle(edit.title!);
    if (edit.artist != null) metadata.setArtist(edit.artist!);
    if (edit.album != null) metadata.setAlbum(edit.album!);
    if (edit.genre != null) metadata.setGenres([edit.genre!]);
    if (edit.trackNumber != null) metadata.setTrackNumber(edit.trackNumber);
    if (edit.discNumber != null) metadata.setCD(edit.discNumber, null);
    if (edit.year != null) metadata.setYear(DateTime(edit.year!));
  });
}

/// Applies tag edits to the audio file and the library row.
///
/// The library is always updated, even when the file write fails (read-only
/// storage, an unsupported container, a format the writer can't round-trip) —
/// otherwise a failed write would leave the user with no way to fix bad tags.
class TagWriter {
  TagWriter(this.db);

  final AppDatabase db;

  /// Returns null on full success, or a message describing why the file itself
  /// could not be updated while the library was.
  Future<String?> apply(Track track, TagEdit edit) async {
    String? fileError;
    try {
      await Isolate.run(() => _writeTags((path: track.filePath, edit: edit)));
    } catch (e) {
      fileError = 'Library updated, but the file tags could not be written '
          '(${e.runtimeType})';
    }

    await db.updateTrackTags(
      track.id,
      title: edit.title == null ? const Value.absent() : Value(edit.title!),
      artist: edit.artist == null ? const Value.absent() : Value(edit.artist!),
      album: edit.album == null ? const Value.absent() : Value(edit.album!),
      genre: edit.genre == null ? const Value.absent() : Value(edit.genre),
      trackNumber: edit.trackNumber == null
          ? const Value.absent()
          : Value(edit.trackNumber),
      discNumber: edit.discNumber == null
          ? const Value.absent()
          : Value(edit.discNumber),
      year: edit.year == null ? const Value.absent() : Value(edit.year),
    );

    return fileError;
  }
}
