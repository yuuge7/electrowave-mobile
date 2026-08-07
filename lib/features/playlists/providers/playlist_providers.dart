import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../models/smart_playlist.dart';
import '../services/smart_playlist_query.dart';

final playlistsProvider = StreamProvider<List<PlaylistWithCount>>((ref) {
  return ref.watch(databaseProvider).watchPlaylists();
});

final playlistProvider = StreamProvider.family<Playlist?, int>((
  ref,
  playlistId,
) {
  return ref.watch(databaseProvider).watchPlaylist(playlistId);
});

final playlistTracksProvider = StreamProvider.family<List<Track>, int>((
  ref,
  playlistId,
) {
  return ref.watch(databaseProvider).watchPlaylistTracks(playlistId);
});

// ---------------------------------------------------------------------------
// Smart playlists
// ---------------------------------------------------------------------------

final smartPlaylistsProvider = StreamProvider<List<SmartPlaylist>>((ref) {
  return ref.watch(databaseProvider).watchSmartPlaylists();
});

final smartPlaylistProvider = StreamProvider.family<SmartPlaylist?, int>((
  ref,
  id,
) {
  return ref.watch(databaseProvider).watchSmartPlaylist(id);
});

final smartPlaylistDefinitionProvider =
    Provider.family<SmartPlaylistDefinition?, int>((ref, id) {
      final row = ref.watch(smartPlaylistProvider(id)).value;
      return row == null ? null : SmartPlaylistDefinition.decode(row.rulesJson);
    });

/// Tracks currently matching a smart playlist's rules.
///
/// Watching the definition through a provider rather than chaining the two
/// streams keeps the query swap simple: an edited rule set rebuilds this
/// provider, which tears down the old query stream and opens the new one.
final smartPlaylistTracksProvider = StreamProvider.family<List<Track>, int>((
  ref,
  id,
) {
  final definition = ref.watch(smartPlaylistDefinitionProvider(id));
  if (definition == null) return Stream.value(const <Track>[]);
  return watchSmartPlaylistTracks(ref.watch(databaseProvider), definition);
});

/// Live preview for the editor, where the rules aren't saved yet. Keyed by the
/// encoded definition because family keys are compared by value and the
/// definition itself has no equality.
final smartPlaylistPreviewProvider = StreamProvider.family<List<Track>, String>(
  (ref, encoded) {
    return watchSmartPlaylistTracks(
      ref.watch(databaseProvider),
      SmartPlaylistDefinition.decode(encoded),
    );
  },
);
