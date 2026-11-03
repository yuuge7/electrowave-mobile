import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'backup_service.dart';
import '../../../core/services/local_log.dart';

class AutomaticBackups {
  static const channel = MethodChannel('electrowave/platform');
  static Future<String?> chooseFolder() =>
      channel.invokeMethod<String>('pickBackupFolder');
  static Future<void> configure(String? uri) =>
      channel.invokeMethod('configureBackups', {'uri': uri});
  static bool _running = false;
  static Future<void> run(
    BackupService service,
    String uri, {
    bool force = false,
  }) async {
    if (_running) return;
    _running = true;
    try {
      final support = await getApplicationSupportDirectory();
      final last = File('${support.path}/last_automatic.ewbackup');
      if (!force &&
          await last.exists() &&
          DateTime.now().difference(await last.lastModified()) <
              const Duration(days: 7)) {
        return;
      }
      final bytes = await service.createBackup();
      await channel.invokeMethod('writeBackup', {'uri': uri, 'bytes': bytes});
      final temp = File('${last.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(last.path);
    } catch (e, s) {
      LocalLog.record(e, s);
      rethrow;
    } finally {
      _running = false;
    }
  }
}
