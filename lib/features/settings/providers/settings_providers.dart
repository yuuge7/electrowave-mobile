import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../library/providers/library_providers.dart';
import '../services/backup_service.dart';

final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));

/// IDs of library tracks whose files no longer exist on disk (e.g. after a
/// backup import onto a device with different files). Flagged in the UI and
/// skipped by playback instead of crashing it.
final missingFilesProvider = FutureProvider<Set<int>>((ref) async {
  final tracks = await ref.watch(libraryTracksProvider.future);
  final missing = <int>{};
  for (final track in tracks) {
    if (!await File(track.filePath).exists()) {
      missing.add(track.id);
    }
  }
  return missing;
});
