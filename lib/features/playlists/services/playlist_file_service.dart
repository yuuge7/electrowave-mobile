import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/database.dart';

class PlaylistFileService {
  PlaylistFileService(this.db);
  final AppDatabase db;
  static String encode(List<Track> tracks) =>
      '#EXTM3U\n${tracks.map((t) => '#EXTINF:${t.durationMs ~/ 1000},${t.artist.replaceAll(RegExp(r'[\r\n]'), ' ')} - ${t.title.replaceAll(RegExp(r'[\r\n]'), ' ')}\n${t.filePath.replaceAll(RegExp(r'[\r\n]'), '')}').join('\n')}\n';
  static List<String> paths(String contents) => const LineSplitter()
      .convert(contents.replaceFirst('\ufeff', ''))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !s.startsWith('#') && !s.contains('://'))
      .toList();
  Future<String?> export(String name, List<Track> tracks) =>
      FilePicker.platform.saveFile(
        dialogTitle: 'Export playlist',
        fileName: '${name.replaceAll(RegExp(r'[^\w -]'), '_')}.m3u8',
        bytes: Uint8List.fromList(utf8.encode(encode(tracks))),
        type: FileType.any,
      );
  Future<String?> import() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.singleOrNull;
    if (picked == null) return null;
    final bytes = picked.bytes ?? await File(picked.path!).readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    final library = await db.watchLibrary().first;
    final exact = {for (final t in library) p.normalize(t.filePath): t};
    final ids = <int>[];
    var missing = 0;
    for (final path in paths(text)) {
      final normalized = p.normalize(path.replaceAll('\\', '/'));
      var track = exact[normalized];
      if (track == null && picked.path != null) {
        track = exact[p.normalize(p.join(p.dirname(picked.path!), normalized))];
      }
      if (track == null) {
        final matches = library
            .where(
              (t) =>
                  t.filePath.replaceAll('\\', '/').endsWith(normalized) ||
                  p.basename(t.filePath) == p.basename(normalized),
            )
            .toList();
        if (matches.length == 1) track = matches.single;
      }
      if (track == null) {
        missing++;
      } else {
        ids.add(track.id);
      }
    }
    if (ids.isEmpty) {
      return 'No matching tracks. Scan the music first ($missing unresolved paths).';
    }
    await db.createPlaylistWithTracks(
      p.basenameWithoutExtension(picked.name),
      ids,
    );
    return 'Imported ${ids.toSet().length} tracks${missing == 0 ? '' : ' · $missing unresolved paths'}';
  }
}

class StatsExport {
  static Future<String?> save(AppDatabase db, {required bool csv}) async {
    final tracks = await db.select(db.tracks).get();
    final sessions = await db.select(db.listeningSessions).get();
    final history = await db.select(db.playbackHistory).get();
    final totals = <int, int>{};
    for (final s in sessions) {
      totals.update(
        s.trackId,
        (v) => v + s.listenedMs,
        ifAbsent: () => s.listenedMs,
      );
    }
    String cell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final text = csv
        ? [
            'id,title,artist,album,plays,listened_ms,starts,skips,rating',
            for (final t in tracks)
              [
                t.id,
                t.title,
                t.artist,
                t.album,
                t.totalPlayCount,
                totals[t.id] ?? 0,
                t.startCount,
                t.skipCount,
                t.rating,
              ].map(cell).join(','),
          ].join('\r\n')
        : const JsonEncoder.withIndent('  ').convert({
            'format': 'Electrowave stats',
            'exportedAt': DateTime.now().toIso8601String(),
            'tracks': tracks.map((t) => t.toJson()).toList(),
            'plays': history.map((h) => h.toJson()).toList(),
            'listeningSessions': sessions.map((s) => s.toJson()).toList(),
          });
    return FilePicker.platform.saveFile(
      dialogTitle: 'Export listening stats',
      fileName: 'electrowave-stats.${csv ? 'csv' : 'json'}',
      type: FileType.any,
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }
}
