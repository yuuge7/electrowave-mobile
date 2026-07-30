import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database.dart';

const String kStagedImportFileName = 'staged_import.db';

class BackupService {
  BackupService(this.db);

  final AppDatabase db;

  /// Export a consistent snapshot of the database to a user-chosen location.
  /// Returns the saved path, or null when the user cancelled.
  Future<String?> exportDatabase() async {
    final support = await getApplicationSupportDirectory();
    final snapshot = File(p.join(support.path, 'export_snapshot.db'));
    if (await snapshot.exists()) await snapshot.delete();

    await db.exportTo(snapshot.path);
    final bytes = await snapshot.readAsBytes();
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Electrowave backup',
      fileName: 'electrowave-backup-$stamp.db',
      type: FileType.any,
      bytes: bytes,
    );
    await snapshot.delete();
    return savedPath;
  }

  /// Let the user pick a backup file and stage it. The staged file replaces
  /// the live database on the next launch (the DB can't be swapped while
  /// open). Returns true when a file was staged.
  Future<bool> stageImport() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose Electrowave backup',
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return false;

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || !_looksLikeSqlite(bytes)) {
      throw const FormatException('Not a valid SQLite database file');
    }

    final docs = await getApplicationDocumentsDirectory();
    final staged = File(p.join(docs.path, kStagedImportFileName));
    await staged.writeAsBytes(bytes, flush: true);
    return true;
  }

  static bool _looksLikeSqlite(Uint8List bytes) {
    const header = 'SQLite format 3';
    if (bytes.length < header.length) return false;
    for (var i = 0; i < header.length; i++) {
      if (bytes[i] != header.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// Called from main() before the database is opened: apply a staged import
  /// if one is waiting. Returns true when an import was applied.
  static Future<bool> applyStagedImportIfAny() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final staged = File(p.join(docs.path, kStagedImportFileName));
      if (!await staged.exists()) return false;

      final live = File(p.join(docs.path, kDatabaseFileName));
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('${live.path}$suffix');
        if (await f.exists()) await f.delete();
      }
      await staged.rename(live.path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
