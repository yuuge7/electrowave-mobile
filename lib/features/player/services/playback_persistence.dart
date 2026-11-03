import 'dart:convert';
import 'dart:io';
import '../../../core/services/local_log.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Snapshot of the playback session, saved so the queue and position survive
/// process death and are restored (paused) on relaunch.
class PersistedPlayback {
  const PersistedPlayback({
    required this.currentTrackId,
    required this.positionMs,
    required this.contextTrackIds,
    required this.contextName,
    required this.manualQueueIds,
    required this.contextIndex,
    required this.shuffle,
    required this.shuffleOrder,
    required this.repeatIndex,
    required this.fromManualQueue,
  });

  final int? currentTrackId;
  final int positionMs;
  final List<int> contextTrackIds;
  final String contextName;
  final List<int> manualQueueIds;
  final int contextIndex;
  final bool shuffle;
  final List<int> shuffleOrder;
  final int repeatIndex;
  final bool fromManualQueue;

  Map<String, dynamic> toJson() => {
    'currentTrackId': currentTrackId,
    'positionMs': positionMs,
    'contextTrackIds': contextTrackIds,
    'contextName': contextName,
    'manualQueueIds': manualQueueIds,
    'contextIndex': contextIndex,
    'shuffle': shuffle,
    'shuffleOrder': shuffleOrder,
    'repeatIndex': repeatIndex,
    'fromManualQueue': fromManualQueue,
  };

  static PersistedPlayback? fromJson(Map<String, dynamic> json) {
    try {
      return PersistedPlayback(
        currentTrackId: json['currentTrackId'] as int?,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        contextTrackIds: (json['contextTrackIds'] as List? ?? const [])
            .cast<int>(),
        contextName: json['contextName'] as String? ?? '',
        manualQueueIds: (json['manualQueueIds'] as List? ?? const [])
            .cast<int>(),
        contextIndex: (json['contextIndex'] as num?)?.toInt() ?? -1,
        shuffle: json['shuffle'] as bool? ?? false,
        shuffleOrder: (json['shuffleOrder'] as List? ?? const []).cast<int>(),
        repeatIndex: (json['repeatIndex'] as num?)?.toInt() ?? 0,
        fromManualQueue: json['fromManualQueue'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

class PlaybackPersistence {
  File? _file;
  Future<void> _pending = Future.value();
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  Future<File> _stateFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'playback_state.json'));
    return _file!;
  }

  Future<void> save(PersistedPlayback state) {
    _lastSave = DateTime.now();
    _pending = _pending
        .then((_) async {
          final file = await _stateFile();
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(
            jsonEncode(state.toJson()),
            flush: true,
          );
          await temporary.rename(file.path);
        })
        .catchError((Object e, StackTrace s) {
          LocalLog.record(e, s);
        });
    return _pending;
  }

  /// Save at most every [minInterval] — used from the position stream.
  Future<void> saveThrottled(
    PersistedPlayback state, {
    Duration minInterval = const Duration(seconds: 5),
  }) async {
    if (DateTime.now().difference(_lastSave) < minInterval) return;
    await save(state);
  }

  Future<PersistedPlayback?> load() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return PersistedPlayback.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
