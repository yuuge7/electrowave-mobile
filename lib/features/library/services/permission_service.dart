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

  /// True when the playback notification can actually be posted. Android 13+
  /// needs POST_NOTIFICATIONS at runtime: without it the foreground service
  /// still runs and audio still plays, but the notification and lock screen
  /// controls are silently dropped.
  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    return Permission.notification.isGranted;
  }

  /// Requests the notification permission, returning the resulting grant
  /// state. Returns false without prompting when the user has permanently
  /// denied it — the system dialog no longer appears, so the caller has to
  /// send them to app settings ([openSettings]).
  Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    return (await Permission.notification.request()).isGranted;
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
