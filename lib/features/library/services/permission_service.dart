import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum AudioPermissionResult { granted, denied, permanentlyDenied }

class PermissionService {
  /// READ_MEDIA_AUDIO on Android 13+, READ_EXTERNAL_STORAGE fallback below.
  Future<AudioPermissionResult> requestAudioAccess() async {
    if (!Platform.isAndroid) return AudioPermissionResult.granted;

    var status = await Permission.audio.request();
    if (status.isGranted || status.isLimited) {
      return AudioPermissionResult.granted;
    }

    // Older Android: media permissions don't exist, storage does.
    final legacy = await Permission.storage.request();
    if (legacy.isGranted || legacy.isLimited) {
      return AudioPermissionResult.granted;
    }

    if (status.isPermanentlyDenied || legacy.isPermanentlyDenied) {
      return AudioPermissionResult.permanentlyDenied;
    }
    return AudioPermissionResult.denied;
  }

  Future<bool> hasAudioAccess() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.audio.isGranted) return true;
    return Permission.storage.isGranted;
  }

  /// Notification permission (Android 13+) for the playback notification.
  /// Best effort — playback works without it, just without the notification.
  Future<void> requestNotifications() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  /// Battery-optimization exemption. Without it, OEM power managers
  /// (Xiaomi, Huawei, Samsung, ...) may kill playback after a while even
  /// though it runs as a foreground service.
  Future<bool> hasBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// Shows the system "allow app to run in background" dialog.
  Future<bool> requestBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<void> openSettings() => openAppSettings();
}
