import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/services/local_log.dart';
import '../../player/providers/player_providers.dart';
import '../../player/services/widget_service.dart';
import '../providers/settings_providers.dart';
import 'automatic_backups.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  if (!Platform.isAndroid) return '1.5.0';
  return await AutomaticBackups.channel.invokeMethod<String>('version') ??
      '1.5.0';
});
final platformBootstrapProvider = FutureProvider<void>((ref) async {
  if (!Platform.isAndroid) return;
  const channel = AutomaticBackups.channel;
  Future<void> action(String? value) async {
    if (value == null) return;
    final controller = ref.read(playerControllerProvider.notifier);
    await controller.restore();
    if (value == 'favorite') {
      final track = ref.read(playerControllerProvider).current;
      if (track != null) {
        await ref
            .read(databaseProvider)
            .setFavorite(
              track.id,
              !((await ref.read(databaseProvider).trackById(track.id))
                      ?.isFavorite ??
                  false),
            );
      }
      final live = track == null
          ? null
          : await ref.read(databaseProvider).trackById(track.id);
      await WidgetService().update(
        track: live,
        playing: ref.read(audioHandlerProvider).playing,
        positionMs: ref.read(audioHandlerProvider).position.inMilliseconds,
      );
      return;
    }
    if (value == 'resume') {
      // Restoration can be asynchronous on a cold launch.
      await controller.restore();
      if (!ref.read(audioHandlerProvider).playing) {
        await controller.togglePlayPause();
      }
      return;
    }
    final db = ref.read(databaseProvider);
    final tracks =
        await (value == 'favorites' ? db.watchFavorites() : db.watchLibrary())
            .first;
    if (tracks.isNotEmpty) {
      await controller.shufflePlayList(
        tracks,
        value == 'favorites' ? 'Favorites' : 'Library',
      );
    }
  }

  channel.setMethodCallHandler((call) async {
    if (call.method == 'action') await action(call.arguments as String?);
  });
  ref.onDispose(() => channel.setMethodCallHandler(null));
  await channel.invokeMethod('shortcuts');
  await action(await channel.invokeMethod<String>('takeAction'));
  String? previousOutput;
  final outputTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    try {
      final profile = await channel.invokeMethod<String>('output');
      if (profile != null && profile != previousOutput) {
        previousOutput = profile;
        if (ref.read(settingsControllerProvider).eqProfile == profile) return;
        await ref
            .read(settingsControllerProvider.notifier)
            .setEqProfile(profile);
      }
    } catch (e, s) {
      LocalLog.record(e, s);
    }
  });
  ref.onDispose(outputTimer.cancel);
  Future<void> backup() async {
    try {
      final uri = ref.read(settingsControllerProvider).backupFolder;
      if (uri != null) {
        await AutomaticBackups.configure(uri);
        await ref.read(playerControllerProvider.notifier).flushState();
        await AutomaticBackups.run(ref.read(backupServiceProvider), uri);
      }
    } catch (e, s) {
      LocalLog.record(e, s);
    }
  }

  final backupTimer = Timer.periodic(
    const Duration(hours: 12),
    (_) => unawaited(backup()),
  );
  ref.onDispose(backupTimer.cancel);
  // Settings have their own async restore; observe the restored destination.
  ref.listen(settingsControllerProvider, (previous, next) {
    if (previous?.backupFolder != next.backupFolder) unawaited(backup());
  });
  await backup();
});
