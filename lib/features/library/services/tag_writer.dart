import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/database/database.dart';
import 'media_write_access.dart';
import 'riff_tag_writer.dart';

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

enum TagFileResult {
  /// The file now carries the edited tags.
  written,

  /// The edit matched what the file already had; nothing to write back.
  unchanged,

  /// No tag writer for this container — the file was not touched.
  unsupported,
}

/// Applies [edit] to the file at [path] in place.
///
/// Only ever pointed at a private copy (see [TagWriter]). Synchronous and
/// whole-file, so it runs in a worker isolate.
TagFileResult applyTagEditToFile(String path, TagEdit edit) {
  final file = File(path);
  final original = file.readAsBytesSync();

  if (isRiffWave(original)) {
    final updated = rewriteRiffTags(
      original,
      RiffTagEdit(
        info: _riffInfo(edit),
        rewriteId3: (tag) => _rewriteId3Tag(tag, path, edit),
      ),
    );
    if (_sameBytes(original, updated)) return TagFileResult.unchanged;
    file.writeAsBytesSync(updated, flush: true);
    return TagFileResult.written;
  }

  if (!_hasTagWriter(original)) return TagFileResult.unsupported;

  final before = _durationOf(file);
  _updateTags(file, edit);

  // A tag edit must never change the audio. A file the reader can no longer
  // parse, or whose length moved, means the writer damaged it — and the
  // caller then keeps the original.
  final after = readMetadata(file, getImage: false).duration;
  if (before != null &&
      after != null &&
      (before - after).abs() > const Duration(seconds: 1)) {
    throw StateError('Tag writer changed the audio duration');
  }

  return _sameBytes(original, file.readAsBytesSync())
      ? TagFileResult.unchanged
      : TagFileResult.written;
}

void _updateTags(File file, TagEdit edit) {
  updateMetadata(file, (metadata) {
    if (edit.title != null) metadata.setTitle(edit.title!);
    if (edit.artist != null) metadata.setArtist(edit.artist!);
    if (edit.album != null) metadata.setAlbum(edit.album!);
    if (edit.genre != null) metadata.setGenres([edit.genre!]);
    if (edit.trackNumber != null) metadata.setTrackNumber(edit.trackNumber);
    if (edit.discNumber != null) metadata.setCD(edit.discNumber, null);
    if (edit.year != null) metadata.setYear(DateTime(edit.year!));
  });
}

/// RIFF INFO has no disc number field.
Map<String, String> _riffInfo(TagEdit edit) => {
  if (edit.title != null) 'INAM': edit.title!,
  if (edit.artist != null) 'IART': edit.artist!,
  if (edit.album != null) 'IPRD': edit.album!,
  if (edit.genre != null) 'IGNR': edit.genre!,
  if (edit.trackNumber != null) 'ITRK': '${edit.trackNumber}',
  if (edit.year != null) 'ICRD': '${edit.year}',
};

/// A WAV's embedded ID3v2 tag, edited with the regular ID3 writer by giving
/// it a file of its own.
Uint8List _rewriteId3Tag(Uint8List tag, String path, TagEdit edit) {
  final scratch = File('$path.id3');
  try {
    scratch.writeAsBytesSync(tag);
    _updateTags(scratch, edit);
    return scratch.readAsBytesSync();
  } finally {
    if (scratch.existsSync()) scratch.deleteSync();
  }
}

/// Mirrors the container detection in audio_metadata_reader's writer, which
/// silently leaves anything else (Ogg, Opus, untagged MP3, ...) as it is.
bool _hasTagWriter(Uint8List bytes) {
  String at(int offset, int length) =>
      offset >= 0 && offset + length <= bytes.length
      ? String.fromCharCodes(bytes, offset, offset + length)
      : '';
  final end = bytes.length;
  return at(0, 3) == 'ID3' ||
      at(4, 4) == 'ftyp' ||
      at(0, 4) == 'fLaC' ||
      at(end - 128, 3) == 'TAG' ||
      at(end - 32, 8) == 'APETAGEX' ||
      at(end - 160, 8) == 'APETAGEX';
}

Duration? _durationOf(File file) {
  try {
    return readMetadata(file, getImage: false).duration;
  } catch (_) {
    return null;
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Applies tag edits to the audio file and the library row.
///
/// The library is always updated, even when the file write fails (read-only
/// storage, an unsupported container, a format the writer can't round-trip) —
/// otherwise a failed write would leave the user with no way to fix bad tags.
///
/// The file itself is never edited in place: the tags go into a private copy,
/// which replaces the original only once it is complete and checks out. A
/// write that fails halfway therefore costs nothing, and a file whose tags
/// can't be written never triggers a permission prompt.
class TagWriter {
  TagWriter(this.db, {MediaWriteAccess? access})
    : _access = access ?? MediaWriteAccess();

  final AppDatabase db;
  final MediaWriteAccess _access;

  /// Returns null on full success, or a message describing why the file itself
  /// could not be updated while the library was.
  Future<String?> apply(Track track, TagEdit edit) async {
    final fileError = await _writeFile(track.filePath, edit);

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

  Future<String?> _writeFile(String path, TagEdit edit) async {
    File? copy;
    try {
      final dir = await getTemporaryDirectory();
      copy = File(
        p.join(
          dir.path,
          'tag-edit-${DateTime.now().microsecondsSinceEpoch}'
          '${p.extension(path)}',
        ),
      );
      await File(path).copy(copy.path);

      final copyPath = copy.path;
      final result = await Isolate.run(
        () => applyTagEditToFile(copyPath, edit),
      );
      return switch (result) {
        TagFileResult.unsupported => _unsupported,
        TagFileResult.unchanged => null,
        TagFileResult.written => await _replace(path, copyPath),
      };
    } catch (e) {
      return _failed(e);
    } finally {
      if (copy != null && await copy.exists()) await copy.delete();
    }
  }

  /// Puts the edited copy in place of [path].
  Future<String?> _replace(String path, String editedPath) async {
    try {
      // Works for files the app may write directly: ones it created, and
      // anything on storage without scoped-storage rules.
      await _overwrite(path, editedPath);
      return null;
    } on PathAccessException catch (e) {
      // Shared storage owned by someone else (Android 10+ scoped storage, or
      // no WRITE_EXTERNAL_STORAGE on older versions): ask the user.
      if (!Platform.isAndroid) return _failed(e);
    }

    switch (await _access.request(path)) {
      case DeniedWriteGrant():
        return _denied;
      case LegacyWriteGrant():
        if (!(await Permission.storage.request()).isGranted) return _denied;
        await _overwrite(path, editedPath);
        return null;
      case UriWriteGrant(:final uri):
        // The grant covers the content URI, not the path.
        await _access.write(uri, editedPath);
        return null;
    }
  }

  /// Opening for write fails before truncating, so a refused write leaves
  /// the original intact.
  static Future<void> _overwrite(String path, String source) =>
      File(source).openRead().pipe(File(path).openWrite());

  static const _denied =
      'Library updated, but the file was left unchanged: write access was '
      'denied';

  static const _unsupported =
      'Library updated, but the file was left unchanged: tags can’t be '
      'written to this file type';

  static String _failed(Object e) =>
      'Library updated, but the file tags could not be written '
      '(${e.runtimeType})';
}
