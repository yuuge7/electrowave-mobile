import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../../core/database/database.dart';
import '../../../core/services/local_log.dart';

const kStagedImportFileName = 'staged_import.ewbackup';
const kBackupSchemaVersion = 6;
const _supportFiles = ['settings.json', 'playback_state.json', 'library.json'];

class _LimitedBytes extends ByteConversionSinkBase {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int length = 0;
  @override
  void add(List<int> chunk) {
    length += chunk.length;
    if (length > 512 * 1024 * 1024) {
      throw const FormatException('Expanded backup is too large');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

class BackupBundle {
  BackupBundle(this.files);
  final Map<String, Uint8List> files;
  Uint8List encode() {
    final payload = utf8.encode(
      jsonEncode({
        'format': 'Electrowave',
        'version': 1,
        'schema': kBackupSchemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'files': files.map((key, value) => MapEntry(key, base64Encode(value))),
      }),
    );
    if (payload.length > 512 * 1024 * 1024) {
      throw const FormatException('Backup exceeds the 512 MB expanded limit');
    }
    return Uint8List.fromList(gzip.encode(payload));
  }

  static BackupBundle decode(List<int> bytes) {
    if (bytes.length > 512 * 1024 * 1024) {
      throw const FormatException('Backup is too large');
    }
    if (bytes.length >= 16 &&
        ascii.decode(bytes.take(15).toList(), allowInvalid: true) ==
            'SQLite format 3') {
      return BackupBundle({'database': Uint8List.fromList(bytes)});
    }
    final sink = _LimitedBytes();
    final decoder = gzip.decoder.startChunkedConversion(sink);
    decoder.add(bytes);
    decoder.close();
    final payload = jsonDecode(utf8.decode(sink.bytes.takeBytes()));
    if (payload is! Map ||
        payload['format'] != 'Electrowave' ||
        payload['version'] != 1 ||
        payload['schema'] is! int ||
        payload['schema'] > kBackupSchemaVersion ||
        payload['files'] is! Map) {
      throw const FormatException(
        'Unsupported Electrowave backup (or made by a newer app)',
      );
    }
    final files = <String, Uint8List>{};
    for (final entry in (payload['files'] as Map).entries) {
      final name = entry.key as String;
      if (name != 'database' &&
          !_supportFiles.contains(name) &&
          !(name.startsWith('albumart/') &&
              p.basename(name) == name.substring(9) &&
              !['.', '..', ''].contains(name.substring(9)))) {
        throw const FormatException('Unexpected backup entry');
      }
      files[name] = base64Decode(entry.value as String);
    }
    if (!files.containsKey('database')) {
      throw const FormatException('Backup has no database');
    }
    for (final name in _supportFiles) {
      if (files[name] != null &&
          jsonDecode(utf8.decode(files[name]!)) is! Map) {
        throw FormatException('Invalid $name');
      }
    }
    return BackupBundle(files);
  }
}

class BackupService {
  BackupService(this.db, {this.documents, this.supportDirectory});
  final Directory? documents, supportDirectory;
  final AppDatabase db;
  static void validateDatabase(String path) {
    final raw = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final version =
          raw.select('PRAGMA user_version').first.values.first as int;
      if (version < 1 || version > kBackupSchemaVersion) {
        throw const FormatException('Unsupported database version');
      }
      if (raw.select('PRAGMA quick_check').any((r) => r.values.first != 'ok')) {
        throw const FormatException('Database is damaged');
      }
      final required = {
        'tracks': [
          'id',
          'file_path',
          'title',
          'artist',
          'album',
          'duration_ms',
          'is_deleted',
          'total_play_count',
        ],
        'playback_history': ['id', 'track_id', 'played_at'],
        'playlists': ['id', 'name', 'created_at'],
        'playlist_tracks': ['playlist_id', 'track_id', 'position'],
      };
      if (version >= 2) {
        required['tracks']!.addAll([
          'is_favorite',
          'track_number',
          'disc_number',
          'year',
        ]);
      }
      if (version >= 3) {
        required['listening_sessions'] = [
          'id',
          'track_id',
          'started_at',
          'listened_ms',
        ];
      }
      if (version >= 4) {
        required['smart_playlists'] = [
          'id',
          'name',
          'rules_json',
          'created_at',
        ];
      }
      if (version >= 5) {
        required['playlists']!.add('pinned_at');
        required['smart_playlists']!.add('pinned_at');
      }
      if (version >= 6) {
        required['tracks']!.addAll([
          'album_artist',
          'file_size',
          'file_modified_ms',
          'rating',
          'replay_gain_db',
          'skip_count',
          'start_count',
        ]);
      }
      for (final table in required.entries) {
        final columns = raw
            .select('PRAGMA table_info(${table.key})')
            .map((r) => r['name'])
            .toSet();
        if (!columns.containsAll(table.value)) {
          throw const FormatException('This is not an Electrowave database');
        }
      }
      if (raw.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw const FormatException('Broken library references');
      }
    } finally {
      raw.close();
    }
  }

  static Future<BackupBundle> _collect(
    Directory docs,
    Directory support,
    Uint8List database,
  ) async {
    final files = <String, Uint8List>{'database': database};
    for (final name in _supportFiles) {
      final f = File(p.join(support.path, name));
      files[name] = await f.exists()
          ? await f.readAsBytes()
          : Uint8List.fromList(
              utf8.encode(
                name == 'playback_state.json'
                    ? '{"currentTrackId":null}'
                    : '{}',
              ),
            );
    }
    final art = Directory(p.join(docs.path, 'albumart'));
    if (await art.exists()) {
      await for (final f in art.list()) {
        if (f is File) {
          files['albumart/${p.basename(f.path)}'] = await f.readAsBytes();
        }
      }
    }
    return BackupBundle(files);
  }

  Future<Uint8List>? _creating;
  Future<Uint8List> createBackup() =>
      _creating ??= _createBackup().whenComplete(() => _creating = null);
  Future<Uint8List> _createBackup() async {
    final docs = documents ?? await getApplicationDocumentsDirectory();
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    final snapshot = File(
      p.join(
        support.path,
        'export_snapshot_${DateTime.now().microsecondsSinceEpoch}_${Isolate.current.hashCode}.db',
      ),
    );
    try {
      await db.exportTo(snapshot.path);
      validateDatabase(snapshot.path);
      final bundle = await _collect(
        docs,
        support,
        await snapshot.readAsBytes(),
      );
      return await Isolate.run(bundle.encode);
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Future<String?> exportDatabase() async => FilePicker.platform.saveFile(
    dialogTitle: 'Export Electrowave backup',
    fileName:
        'electrowave-${DateTime.now().toIso8601String().replaceAll(':', '-')}.ewbackup',
    type: FileType.any,
    bytes: await createBackup(),
  );
  Future<bool> stageImport() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose Electrowave backup',
      type: FileType.any,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return false;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const FormatException('Could not read backup');
    await stageBytes(bytes);
    return true;
  }

  static Future<void> stageBytes(
    List<int> bytes, {
    Directory? documents,
  }) async {
    final bundle = BackupBundle.decode(bytes);
    final docs = documents ?? await getApplicationDocumentsDirectory();
    final probe = File(p.join(docs.path, 'import-validation.db'));
    try {
      await probe.writeAsBytes(bundle.files['database']!, flush: true);
      validateDatabase(probe.path);
      final staged = File(p.join(docs.path, kStagedImportFileName));
      final temporary = File('${staged.path}.tmp');
      await temporary.writeAsBytes(bundle.encode(), flush: true);
      await temporary.rename(staged.path);
    } finally {
      if (await probe.exists()) await probe.delete();
    }
  }

  static Future<bool> applyStagedImportIfAny({
    Directory? documents,
    Directory? supportDirectory,
  }) async {
    final docs = documents ?? await getApplicationDocumentsDirectory();
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    final journal = Directory(p.join(docs.path, 'restore-journal'));
    Future<void> rollback() async {
      if (!await journal.exists()) return;
      final manifest = File(p.join(journal.path, 'manifest.json'));
      if (!await manifest.exists()) {
        await journal.delete(recursive: true);
        return;
      }
      final paths = (jsonDecode(await manifest.readAsString()) as List)
          .cast<String>();
      for (var i = 0; i < paths.length; i++) {
        final original = File(p.join(journal.path, '$i'));
        final target = File(paths[i]);
        if (await target.exists()) await target.delete();
        if (await original.exists()) await original.copy(target.path);
      }
      await journal.delete(recursive: true);
    }

    await rollback();
    final staged = File(p.join(docs.path, kStagedImportFileName));
    final legacy = File(p.join(docs.path, 'staged_import.db'));
    final source = await staged.exists() ? staged : legacy;
    if (!await source.exists()) return false;
    try {
      final bundle = BackupBundle.decode(await source.readAsBytes());
      final replacement = File(p.join(docs.path, 'validated-import.db'));
      await replacement.writeAsBytes(bundle.files['database']!, flush: true);
      validateDatabase(replacement.path);
      final live = File(p.join(docs.path, kDatabaseFileName));
      if (await live.exists()) {
        final snapshot = File(p.join(docs.path, 'before-import.db'));
        try {
          if (await snapshot.exists()) await snapshot.delete();
          final raw = sqlite3.open(live.path);
          try {
            raw.execute('VACUUM INTO ?', [snapshot.path]);
          } finally {
            raw.close();
          }
          final safety = await _collect(
            docs,
            support,
            await snapshot.readAsBytes(),
          );
          await File(
            p.join(docs.path, 'restore-safety.ewbackup'),
          ).writeAsBytes(safety.encode(), flush: true);
        } catch (e, s) {
          LocalLog.record(e, s);
          rethrow;
        } finally {
          if (await snapshot.exists()) await snapshot.delete();
        }
      }
      final targets = <String, Uint8List?>{
        live.path: bundle.files['database'],
        for (final suffix in ['-wal', '-shm', '-journal'])
          '${live.path}$suffix': null,
        // Legacy backups preserve existing settings instead of resetting them.
        for (final name in _supportFiles)
          if (bundle.files[name] != null)
            p.join(support.path, name): bundle.files[name],
        for (final entry in bundle.files.entries.where(
          (e) => e.key.startsWith('albumart/'),
        ))
          p.join(docs.path, entry.key): entry.value,
      };
      await journal.create();
      final paths = targets.keys.toList();
      for (var i = 0; i < paths.length; i++) {
        final f = File(paths[i]);
        if (await f.exists()) await f.copy(p.join(journal.path, '$i'));
      }
      await File(
        p.join(journal.path, 'manifest.json'),
      ).writeAsString(jsonEncode(paths), flush: true);
      for (final entry in targets.entries) {
        final f = File(entry.key);
        if (await f.exists()) await f.delete();
        if (entry.value != null) {
          await f.parent.create(recursive: true);
          await f.writeAsBytes(entry.value!, flush: true);
        }
      }
      // Relocate cached artwork, whose original sandbox differs on a new phone.
      final raw = sqlite3.open(live.path);
      try {
        for (final row in raw.select(
          'SELECT id,album_art_path FROM tracks WHERE album_art_path IS NOT NULL',
        )) {
          final name = p.basename(row['album_art_path'] as String);
          if (bundle.files.containsKey('albumart/$name')) {
            raw.execute('UPDATE tracks SET album_art_path=? WHERE id=?', [
              p.join(docs.path, 'albumart', name),
              row['id'],
            ]);
          }
        }
      } finally {
        raw.close();
      }
      await source.delete();
      await journal.delete(recursive: true);
      await replacement.delete();
      return true;
    } catch (e, s) {
      await rollback();
      LocalLog.record(e, s);
      rethrow;
    }
  }
}
