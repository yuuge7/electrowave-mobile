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

  Future<void> update({Track? track, required bool playing}) async {
    if (!_supported) return;

    // Called from the playback state stream, so skip redundant IPC when
    // nothing the widget shows has actually changed.
    final key = '${track?.id}|$playing';
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
      await HomeWidget.updateWidget(androidName: _androidProvider);
    } catch (_) {
      // No widget placed, or the platform channel isn't available — neither
      // is worth interrupting playback for.
    }
  }
}
