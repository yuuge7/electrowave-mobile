import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'core/services/local_log.dart';
import 'core/theme/theme.dart';
import 'features/settings/views/recovery_screen.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/database/database.dart';
import 'core/database/database_provider.dart';
import 'features/player/providers/player_providers.dart';
import 'features/player/services/audio_handler.dart';
import 'features/settings/services/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalLog.initialize();
  MediaKit.ensureInitialized();
  await bootstrap();
}

Future<void> bootstrap() async {
  AppDatabase? opening;
  try {
    // A staged backup import (Settings → Import) is applied before the
    // database is opened — it can't be swapped while in use.
    final importApplied = await BackupService.applyStagedImportIfAny();

    final file = await databaseFile();
    if (await file.exists()) BackupService.validateDatabase(file.path);
    final database = AppDatabase();
    opening = database;
    await database.customSelect('SELECT 1').get();

    final audioHandler = await AudioService.init(
      builder: ElectrowaveAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.electrowave.playback',
        androidNotificationChannelName: 'Playback',
        // Monochrome white-on-transparent glyph. The default
        // (mipmap/ic_launcher) is fully opaque, and Android masks small icons
        // through their alpha channel, so it renders as a solid white square
        // and stops some devices drawing the notification seek bar.
        androidNotificationIcon: 'drawable/ic_stat_electrowave',
        // Must be non-transparent for the seek bar to render (audio_service).
        notificationColor: Color(0xFF0D1B1E),
        // Must stay false: media_kit emits a brief playing=false at every track
        // transition, and leaving the foreground state there releases the wake
        // lock exactly when Dart needs CPU to open the next file — with the
        // screen off / device dozing, playback dies mid-queue. The handler
        // stops the service itself after a prolonged pause instead.
        // (androidNotificationOngoing must be false when this is false.)
        androidStopForegroundOnPause: false,
      ),
    );

    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          audioHandlerProvider.overrideWithValue(audioHandler),
          importAppliedProvider.overrideWithValue(importApplied),
        ],
        child: const ElectrowaveApp(),
      ),
    );
  } catch (e, s) {
    await opening?.close();
    LocalLog.record(e, s);
    runApp(
      MaterialApp(
        title: 'Electrowave',
        debugShowCheckedModeBanner: false,
        theme: ElectrowaveTheme.build(ElectrowaveTheme.darkScheme),
        home: RecoveryScreen(error: e, retry: bootstrap),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> backupWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  const worker = MethodChannel('electrowave/backup_worker');
  AppDatabase? db;
  var success = false;
  try {
    await LocalLog.initialize();
    final uri = await worker.invokeMethod<String>('config');
    if (uri != null) {
      db = AppDatabase();
      final bytes = await BackupService(db).createBackup();
      await worker.invokeMethod('write', {'uri': uri, 'bytes': bytes});
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/last_automatic.ewbackup.tmp');
      await file.writeAsBytes(bytes, flush: true);
      await file.rename('${dir.path}/last_automatic.ewbackup');
    }
    success = true;
  } catch (e, s) {
    LocalLog.record(e, s);
  } finally {
    await db?.close();
    await worker.invokeMethod('finished', success);
  }
}
