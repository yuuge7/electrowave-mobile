import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../services/library_scanner.dart';
import '../services/permission_service.dart';
import '../services/tag_writer.dart';

final permissionServiceProvider =
    Provider<PermissionService>((ref) => PermissionService());

final libraryScannerProvider = Provider<LibraryScanner>(
    (ref) => LibraryScanner(ref.watch(databaseProvider)));

final tagWriterProvider =
    Provider<TagWriter>((ref) => TagWriter(ref.watch(databaseProvider)));

final librarySearchProvider = StateProvider<String>((ref) => '');

final librarySortProvider =
    StateProvider<LibrarySort>((ref) => LibrarySort.title);

final libraryTracksProvider = StreamProvider<List<Track>>((ref) {
  final db = ref.watch(databaseProvider);
  final search = ref.watch(librarySearchProvider);
  final sort = ref.watch(librarySortProvider);
  return db.watchLibrary(search: search, sort: sort);
});

/// Remembers the last scanned folder so Settings can offer "re-scan".
final lastScannedFolderProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Scanning
// ---------------------------------------------------------------------------

class ScanState {
  const ScanState({
    this.running = false,
    this.total = 0,
    this.processed = 0,
    this.failed = 0,
    this.message,
  });

  final bool running;
  final int total;
  final int processed;
  final int failed;

  /// One-shot result message shown after a scan completes.
  final String? message;

  ScanState copyWith({
    bool? running,
    int? total,
    int? processed,
    int? failed,
    String? message,
    bool clearMessage = false,
  }) {
    return ScanState(
      running: running ?? this.running,
      total: total ?? this.total,
      processed: processed ?? this.processed,
      failed: failed ?? this.failed,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanState>(ScanController.new);

class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  PermissionService get _permissions => ref.read(permissionServiceProvider);
  LibraryScanner get _scanner => ref.read(libraryScannerProvider);

  void clearMessage() => state = state.copyWith(clearMessage: true);

  /// Returns false when permission was denied (UI should show the explainer).
  Future<bool> pickAndScanFolder() async {
    final permission = await _permissions.requestAudioAccess();
    if (permission != AudioPermissionResult.granted) return false;

    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose your music folder',
    );
    if (folder == null) return true; // user cancelled
    ref.read(lastScannedFolderProvider.notifier).state = folder;
    await scanFolder(folder);
    return true;
  }

  Future<bool> pickAndScanFiles() async {
    final permission = await _permissions.requestAudioAccess();
    if (permission != AudioPermissionResult.granted) return false;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose audio files',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        for (final e in kAudioExtensions) e.replaceFirst('.', ''),
      ],
    );
    final paths = result?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty) return true;
    await _runScan(paths);
    return true;
  }

  Future<void> scanFolder(String folder) async {
    if (state.running) return;
    state = const ScanState(running: true);
    final files = await _scanner.collectAudioFiles(folder);
    await _runScan(files, preCollected: true);
  }

  Future<void> _runScan(List<String> files, {bool preCollected = false}) async {
    if (!preCollected && state.running) return;
    state = ScanState(running: true, total: files.length);
    var processed = 0;
    var failed = 0;
    for (final file in files) {
      final ok = await _scanner.importFile(file);
      processed++;
      if (!ok) failed++;
      if (processed % 5 == 0 || processed == files.length) {
        state = state.copyWith(
          total: files.length,
          processed: processed,
          failed: failed,
        );
      }
    }
    state = ScanState(
      running: false,
      total: files.length,
      processed: processed,
      failed: failed,
      message: files.isEmpty
          ? 'No audio files found'
          : 'Scanned ${files.length} file${files.length == 1 ? '' : 's'}'
              '${failed > 0 ? ' ($failed failed)' : ''}',
    );
  }
}
