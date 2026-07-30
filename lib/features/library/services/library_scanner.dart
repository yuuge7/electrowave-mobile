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
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int durationMs;
  final Uint8List? artBytes;
  final String? artMime;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
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
      trackNumber: meta.trackNumber,
      discNumber: meta.discNumber,
      year: meta.year?.year,
    );
  } catch (_) {
    return const ParsedTags(); // Unreadable tags: fall back to filename.
  }
}

/// Cover images to look for next to the audio file when a track carries no
/// embedded art — the common layout for CD rips and Bandcamp downloads.
const List<String> kFolderArtNames = [
  'cover',
  'folder',
  'front',
  'album',
  'albumart',
  'artwork',
  'thumb',
];

const List<String> kFolderArtExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

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
      } else {
        // No embedded art: fall back to a cover image sitting in the same
        // folder. Referenced in place — no need to copy it into app storage.
        artPath = await _findFolderArt(p.dirname(filePath));
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
        trackNumber: Value(meta.trackNumber),
        discNumber: Value(meta.discNumber),
        year: Value(meta.year),
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Folders are looked up once and cached: a scan walks an album directory
  /// track by track, so this would otherwise stat the same files repeatedly.
  final Map<String, String?> _folderArtCache = {};

  Future<String?> _findFolderArt(String folderPath) async {
    if (_folderArtCache.containsKey(folderPath)) {
      return _folderArtCache[folderPath];
    }

    String? found;
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        // Index the folder's image files once, then pick by preference order
        // so 'cover.jpg' wins over 'thumb.png' regardless of listing order.
        final images = <String, String>{};
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!kFolderArtExtensions.contains(ext)) continue;
          final stem = p.basenameWithoutExtension(entity.path).toLowerCase();
          images.putIfAbsent(stem, () => entity.path);
        }

        for (final name in kFolderArtNames) {
          if (images.containsKey(name)) {
            found = images[name];
            break;
          }
        }
        // Nothing conventionally named: accept a lone image in the folder.
        if (found == null && images.length == 1) {
          found = images.values.first;
        }
      }
    } on FileSystemException {
      // Unreadable directory: treat as "no art".
    }

    _folderArtCache[folderPath] = found;
    return found;
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
