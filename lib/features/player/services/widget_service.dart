import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../../../core/database/database.dart';

/// Pushes the current track into the home screen widget.
///
/// The widget's buttons broadcast media key events straight to audio_service,
/// so this only ever writes display data — there is no command channel to
/// maintain in the other direction.
class WidgetService {
  static const _androidProvider = 'ElectrowaveWidgetProvider';

  String? _lastKey;

  /// Android only; a no-op elsewhere so callers don't need a platform check.
  bool get _supported => Platform.isAndroid;

  Future<void> update({
    Track? track,
    required bool playing,
    int positionMs = 0,
  }) async {
    if (!_supported) return;

    // Called from the playback state stream, so skip redundant IPC when
    // nothing the widget shows has actually changed.
    final key =
        '${track?.id}|${track?.title}|${track?.artist}|${track?.albumArtPath}|$playing|${track?.isFavorite}|${positionMs ~/ 5000}';
    if (key == _lastKey) return;
    _lastKey = key;

    try {
      await HomeWidget.saveWidgetData<String>('track_title', track?.title);
      await HomeWidget.saveWidgetData<String>('track_artist', track?.artist);
      await HomeWidget.saveWidgetData<String>(
        'track_art',
        (track?.albumArtPath?.isNotEmpty ?? false) ? track!.albumArtPath : null,
      );
      await HomeWidget.saveWidgetData<bool>('is_playing', playing);
      await HomeWidget.saveWidgetData<bool>(
        'track_favorite',
        track?.isFavorite ?? false,
      );
      await HomeWidget.saveWidgetData<int>(
        'track_progress',
        track == null || track.durationMs == 0
            ? 0
            : (positionMs / track.durationMs * 1000).round().clamp(0, 1000),
      );
      for (final provider in [
        _androidProvider,
        'ElectrowaveArtWidgetProvider',
        'ElectrowaveWideWidgetProvider',
      ]) {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: 'com.example.electrowave_mobile.$provider',
        );
      }
    } catch (_) {
      // No widget placed, or the platform channel isn't available — neither
      // is worth interrupting playback for.
    }
  }
}
