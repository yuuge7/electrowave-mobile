import 'dart:io';

import 'package:flutter/services.dart';

/// Why the playback notification is not on screen, in the order the user
/// should fix them.
enum NotificationBlock {
  /// Nothing wrong — it should be visible whenever something is playing.
  none,

  /// Notifications are off for the whole app (POST_NOTIFICATIONS denied, or
  /// switched off in system settings afterwards).
  app,

  /// The app is allowed, but the "Playback" channel itself is switched off.
  /// Permission checks still report "granted" in this state, which is what
  /// makes it so confusing from inside the app.
  channel,

  /// audio_service creates the channel when its foreground service first
  /// starts, so this means playback has not run yet on this install.
  notCreatedYet,
}

/// Reads notification state Android exposes only through the platform APIs —
/// `permission_handler` reports POST_NOTIFICATIONS and nothing else.
class NotificationDiagnostics {
  static const _channel = MethodChannel('electrowave/notifications');

  Future<NotificationBlock> check() async {
    if (!Platform.isAndroid) return NotificationBlock.none;
    try {
      final status =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      if (status['appEnabled'] != true) return NotificationBlock.app;
      if (status['channelBlocked'] == true) return NotificationBlock.channel;
      if (status['channelExists'] != true) {
        return NotificationBlock.notCreatedYet;
      }
      return NotificationBlock.none;
    } on PlatformException {
      return NotificationBlock.none;
    } on MissingPluginException {
      return NotificationBlock.none;
    }
  }

  /// Opens the channel's own settings page when it exists, the app's
  /// notification page otherwise.
  Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Nothing to fall back to from here; the tile stays as it was.
    } on MissingPluginException {
      // Ditto.
    }
  }
}
