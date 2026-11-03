import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded, local-only diagnostics. Never includes audio contents.
class LocalLog {
  static File? _file;
  static Future<void> _pending = Future.value();

  static Future<void> initialize() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/crash.log');
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return true;
    };
  }

  static void record(Object error, [StackTrace? stack]) {
    _pending = _pending
        .then((_) async {
          final file = _file;
          if (file == null) return;
          if (await file.exists() && await file.length() > 256 * 1024) {
            final previous = File('${file.path}.previous');
            if (await previous.exists()) await previous.delete();
            await file.rename(previous.path);
          }
          String bound(String value, int max) =>
              value.length > max ? value.substring(0, max) : value;
          await file.writeAsString(
            '${DateTime.now().toIso8601String()} ${bound(error.toString(), 8192)}\n${bound(stack?.toString() ?? '', 16384)}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object _) {});
  }

  static Future<List<int>> export() async {
    await _pending;
    final file = _file;
    if (file == null) {
      return 'No errors recorded. Diagnostics stay on this device.\n'.codeUnits;
    }
    final files = [
      File('${file.path}.previous'),
      file,
      File('${file.parent.path}/native-crash.log.previous'),
      File('${file.parent.path}/native-crash.log'),
    ];
    final bytes = <int>[];
    for (final part in files) {
      if (await part.exists()) bytes.addAll(await part.readAsBytes());
    }
    return bytes.isEmpty
        ? 'No errors recorded. Diagnostics stay on this device.\n'.codeUnits
        : bytes;
  }
}
