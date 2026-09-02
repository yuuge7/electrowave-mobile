import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/art_accent.dart';
import 'player_providers.dart';

/// Dominant hue of one art file. Kept alive because covers repeat constantly
/// — every track on an album shares one — and re-decoding per row would be
/// pure waste.
final artAccentProvider =
    FutureProvider.family<ArtAccent?, String?>((ref, path) async {
  if (path == null || path.isEmpty) return null;
  ref.keepAlive();
  return extractArtAccent(path);
});

/// The accent of whatever is playing, for the surfaces that follow the music:
/// the now-playing backdrop, the seek rule, the mini player's progress.
final currentAccentProvider = Provider<ArtAccent?>((ref) {
  final art = ref.watch(
    playerControllerProvider.select((s) => s.current?.albumArtPath),
  );
  return ref.watch(artAccentProvider(art)).value;
});
