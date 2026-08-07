import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Close the app outright — used when the sleep timer fires.
///
/// [SystemNavigator.pop] on its own only finishes the activity: the process
/// stays alive with mpv loaded and the playback service attached, which is
/// exactly what "the sleep timer ended" is supposed to end. Killing the
/// process after the activity is gone is the only way to close everything on
/// Android, so anything worth keeping has to be persisted *before* this is
/// called — nothing after it runs.
Future<void> closeApp() async {
  await SystemNavigator.pop(animated: false);
  // Let the activity finish and the platform channel drain first; killing the
  // process in the same microtask leaves the launcher animating a dead task.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  exit(0);
}
