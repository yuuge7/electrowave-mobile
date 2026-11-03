import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../services/library_scanner.dart';
import '../services/library_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import '../services/permission_service.dart';
import '../services/tag_writer.dart';

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);

final libraryScannerProvider = Provider<LibraryScanner>(
  (ref) => LibraryScanner(ref.watch(databaseProvider)),
);

final tagWriterProvider = Provider<TagWriter>(
  (ref) => TagWriter(ref.watch(databaseProvider)),
);

/// Raw text in the search field, written on every keystroke. The field itself
/// watches this, so it is the only place the query string lives — there is no
/// separate `TextEditingController` state to keep in sync.
final librarySearchInputProvider = StateProvider<String>((ref) => '');

/// Debounced view of [librarySearchInputProvider]: the string actually handed
/// to the database.
///
/// The library query is `title LIKE '%x%' OR artist LIKE '%x%' OR album LIKE
/// '%x%'`. A leading wildcard cannot use an index, so every one of those is a
/// full table scan — running one per keystroke means typing an eight-letter
/// artist name scans the whole library eight times.
final librarySearchProvider = NotifierProvider<LibrarySearchQuery, String>(
  LibrarySearchQuery.new,
);

class LibrarySearchQuery extends Notifier<String> {
  static const _debounce = Duration(milliseconds: 250);

  Timer? _timer;

  @override
  String build() {
    ref.listen(librarySearchInputProvider, (_, input) {
      _timer?.cancel();
      // Clearing the field restores the full list and costs nothing, so it
      // should feel instant; only typing waits for the pause.
      if (input.isEmpty) {
        state = '';
        return;
      }
      _timer = Timer(_debounce, () => state = input);
    });
    ref.onDispose(() => _timer?.cancel());
    return ref.read(librarySearchInputProvider);
  }
}

final librarySortProvider = StateProvider<LibrarySort>(
  (ref) => LibrarySort.title,
);

final libraryTracksProvider = StreamProvider<List<Track>>((ref) {
  final db = ref.watch(databaseProvider);
  final search = ref.watch(librarySearchProvider);
  final sort = ref.watch(librarySortProvider);
  return db.watchLibrary(
    search: search,
    sort: sort,
    descending: ref.watch(libraryDescendingProvider),
  );
});

final librarySelectionProvider = StateProvider<Set<int>>((ref) => {});
final libraryDescendingProvider = StateProvider<bool>((ref) => false);
final libraryFoldersProvider = StateProvider<List<String>>((ref) => []);
final libraryPreferencesProvider = FutureProvider<void>((ref) async {
  final saved = await LibraryPreferences.load();
  ref.read(librarySortProvider.notifier).state = saved.sort;
  ref.read(libraryDescendingProvider.notifier).state = saved.descending;
  ref.read(libraryFoldersProvider.notifier).state = saved.folders;
  void persist() => unawaited(
    LibraryPreferences(
      folders: ref.read(libraryFoldersProvider),
      sort: ref.read(librarySortProvider),
      descending: ref.read(libraryDescendingProvider),
    ).save(),
  );
  ref.listen(librarySortProvider, (_, _) => persist());
  ref.listen(libraryDescendingProvider, (_, _) => persist());
  ref.listen(libraryFoldersProvider, (_, _) => persist());
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
    this.folder,
    this.cancelled = false,
    this.skipped = 0,
  });

  final bool running;
  final String? folder;
  final bool cancelled;
  final int skipped;
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
    String? folder,
    bool? cancelled,
    int? skipped,
  }) {
    return ScanState(
      folder: folder ?? this.folder,
      cancelled: cancelled ?? this.cancelled,
      skipped: skipped ?? this.skipped,
      running: running ?? this.running,
      total: total ?? this.total,
      processed: processed ?? this.processed,
      failed: failed ?? this.failed,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);

class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    state = state.copyWith(cancelled: true);
  }

  void forgetFolder(String folder) {
    ref.read(libraryFoldersProvider.notifier).state = [
      ...ref.read(libraryFoldersProvider),
    ]..remove(folder);
  }

  Future<void> rescanAll() => scanFolders(ref.read(libraryFoldersProvider));

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
    ref.read(libraryFoldersProvider.notifier).state = {
      ...ref.read(libraryFoldersProvider),
      folder,
    }.toList();
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

  Future<void> scanFolder(String folder) => scanFolders([folder]);

  Future<void> scanFolders(List<String> folders) async {
    if (state.running) return;
    _cancelled = false;
    state = const ScanState(running: true);
    try {
      final files = <String>{};
      for (final folder in folders) {
        if (_cancelled) break;
        state = state.copyWith(folder: folder);
        files.addAll(
          await _scanner.collectAudioFiles(folder, cancelled: () => _cancelled),
        );
      }
      await _runScan(files.toList(), preCollected: true);
    } catch (e) {
      state = ScanState(message: 'Scan failed: $e');
    }
  }

  Future<void> _runScan(List<String> files, {bool preCollected = false}) async {
    if (!preCollected && state.running) return;
    if (!preCollected) _cancelled = false;
    state = ScanState(running: true, total: files.length);
    var processed = 0, failed = 0, skipped = 0;
    // Cache the fingerprint index once, rather than one query per unchanged file.
    final tracks = await ref
        .read(databaseProvider)
        .select(ref.read(databaseProvider).tracks)
        .get();
    final fingerprints = {for (final t in tracks) t.filePath: t};
    _scanner.clearCaches();
    for (final file in files) {
      if (_cancelled) break;
      try {
        final stat = await File(file).stat();
        final old = fingerprints[file];
        if (old != null &&
            old.fileSize == stat.size &&
            old.fileModifiedMs == stat.modified.millisecondsSinceEpoch) {
          skipped++;
        } else if (!await _scanner.importFile(file)) {
          failed++;
        }
      } catch (_) {
        failed++;
      }
      processed++;
      if (processed % 5 == 0 || processed == files.length) {
        state = state.copyWith(
          processed: processed,
          failed: failed,
          skipped: skipped,
          folder: p.dirname(file),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
    state = ScanState(
      total: files.length,
      processed: processed,
      failed: failed,
      skipped: skipped,
      cancelled: _cancelled,
      message:
          '${_cancelled ? 'Cancelled after' : 'Scanned'} $processed files ($skipped unchanged${failed > 0 ? ', $failed failed' : ''})',
    );
  }
}
