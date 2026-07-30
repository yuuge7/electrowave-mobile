import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database.dart';

const Set<String> kAudioExtensions = {'.mp3', '.flac', '.m4a', '.ogg', '.wav'};

class ScanResult {
  const ScanResult({required this.added, required this.failed});

  final int added;
  final int failed;
}

/// Plain tag data extracted in a worker isolate (tag parsing is synchronous
/// and would jank the UI otherwise).
class ParsedTags {
  const ParsedTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs = 0,
    this.artBytes,
    this.artMime,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int durationMs;
  final Uint8List? artBytes;
  final String? artMime;
}

ParsedTags parseTags(String filePath) {
  try {
    final meta = readMetadata(File(filePath), getImage: true);
    final picture = meta.pictures.isNotEmpty ? meta.pictures.first : null;
    return ParsedTags(
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      genre: meta.genres.isNotEmpty ? meta.genres.first : null,
      durationMs: meta.duration?.inMilliseconds ?? 0,
      artBytes: picture?.bytes,
      artMime: picture?.mimetype,
    );
  } catch (_) {
    return const ParsedTags(); // Unreadable tags: fall back to filename.
  }
}

class LibraryScanner {
  LibraryScanner(this.db);

  final AppDatabase db;

  Directory? _artDir;

  Future<Directory> _albumArtDir() async {
    if (_artDir != null) return _artDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'albumart'));
    await dir.create(recursive: true);
    _artDir = dir;
    return dir;
  }

  /// Recursively collect audio files under [folderPath].
  Future<List<String>> collectAudioFiles(String folderPath) async {
    final result = <String>[];
    final dir = Directory(folderPath);
    if (!await dir.exists()) return result;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File &&
            kAudioExtensions.contains(p.extension(entity.path).toLowerCase())) {
          result.add(entity.path);
        }
      }
    } on FileSystemException {
      // Some subdirectories may be unreadable; keep what we could list.
    }
    result.sort();
    return result;
  }

  /// Import one audio file: read tags + embedded art, upsert into the DB.
  /// Returns true on success.
  Future<bool> importFile(String filePath) async {
    try {
      final meta = await Isolate.run(() => parseTags(filePath));

      final fallbackTitle = p.basenameWithoutExtension(filePath);
      String? artPath;
      if (meta.artBytes != null && meta.artBytes!.isNotEmpty) {
        artPath = await _storeArt(
          meta.artBytes!,
          meta.artMime,
          artist: meta.artist,
          album: meta.album,
          fallbackKey: fallbackTitle,
        );
      }

      await db.upsertScannedTrack(TracksCompanion.insert(
        filePath: filePath,
        title: (meta.title?.trim().isNotEmpty ?? false)
            ? meta.title!.trim()
            : fallbackTitle,
        artist: (meta.artist?.trim().isNotEmpty ?? false)
            ? meta.artist!.trim()
            : 'Unknown artist',
        album: (meta.album?.trim().isNotEmpty ?? false)
            ? meta.album!.trim()
            : 'Unknown album',
        durationMs: meta.durationMs,
        genre: Value(meta.genre?.trim().isNotEmpty ?? false
            ? meta.genre!.trim()
            : null),
        albumArtPath: Value(artPath),
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Album art files are shared per (artist, album) so a thousand-track
  /// album does not store a thousand copies.
  Future<String> _storeArt(
    Uint8List bytes,
    String? mimeType, {
    String? artist,
    String? album,
    required String fallbackKey,
  }) async {
    final dir = await _albumArtDir();
    var key = [
      if (artist != null && artist.trim().isNotEmpty) artist.trim(),
      if (album != null && album.trim().isNotEmpty) album.trim(),
    ].join('_');
    if (key.isEmpty) key = fallbackKey;
    key = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (key.length > 80) key = key.substring(0, 80);

    final ext = (mimeType ?? '').contains('png') ? '.png' : '.jpg';
    final file = File(p.join(dir.path, '$key$ext'));
    if (!await file.exists()) {
      await file.writeAsBytes(bytes);
    }
    return file.path;
  }
}
