import 'package:flutter/services.dart';

/// How the app may modify a file it does not own (see MediaWriteAccess.kt).
sealed class MediaWriteGrant {
  const MediaWriteGrant();
}

/// Android 9 and older: write the path directly once WRITE_EXTERNAL_STORAGE
/// is granted.
class LegacyWriteGrant extends MediaWriteGrant {
  const LegacyWriteGrant();
}

/// Android 10+: the user allowed the write; it has to go through [uri].
class UriWriteGrant extends MediaWriteGrant {
  const UriWriteGrant(this.uri);
  final String uri;
}

/// The user declined the system dialog.
class DeniedWriteGrant extends MediaWriteGrant {
  const DeniedWriteGrant();
}

class MediaWriteAccess {
  static const _channel = MethodChannel('electrowave/media_write');

  /// Asks for write access to [path], showing the system consent dialog when
  /// the app does not hold it yet.
  Future<MediaWriteGrant> request(String path) async {
    final answer = await _channel.invokeMapMethod<String, dynamic>('request', {
      'path': path,
    });
    return switch (answer?['mode']) {
      'legacy' => const LegacyWriteGrant(),
      'uri' => UriWriteGrant(answer!['uri'] as String),
      _ => const DeniedWriteGrant(),
    };
  }

  /// Replaces the content behind [uri] with the bytes of the file at
  /// [sourcePath].
  Future<void> write(String uri, String sourcePath) =>
      _channel.invokeMethod<void>('write', {'uri': uri, 'source': sourcePath});
}
