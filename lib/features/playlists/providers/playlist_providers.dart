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

// ---------------------------------------------------------------------------
// Pinned
// ---------------------------------------------------------------------------

/// A pinned playlist of either kind. Pinning cuts across the manual/smart
/// split: the pinned run is the lists someone reaches for, whatever fills them.
sealed class PinnedPlaylist {
  const PinnedPlaylist();

  String get name;
  DateTime get pinnedAt;

  /// Where the playlist opens, inside the Playlists tab.
  String get location;
}

final class PinnedManualPlaylist extends PinnedPlaylist {
  const PinnedManualPlaylist(this.entry);

  final PlaylistWithCount entry;

  @override
  String get name => entry.playlist.name;
  @override
  DateTime get pinnedAt => entry.playlist.pinnedAt!;
  @override
  String get location => '/playlists/${entry.playlist.id}';
}

final class PinnedSmartPlaylist extends PinnedPlaylist {
  const PinnedSmartPlaylist(this.playlist);

  final SmartPlaylist playlist;

  @override
  String get name => playlist.name;
  @override
  DateTime get pinnedAt => playlist.pinnedAt!;
  @override
  String get location => '/playlists/smart/${playlist.id}';
}

/// Both kinds' pinned playlists as one run, oldest pin first, so pinning a
/// new list adds it at the end rather than reshuffling the ones above.
final pinnedPlaylistsProvider = Provider<List<PinnedPlaylist>>((ref) {
  final manual = ref.watch(playlistsProvider).value ?? const [];
  final smart = ref.watch(smartPlaylistsProvider).value ?? const [];
  return [
    for (final entry in manual)
      if (entry.playlist.pinnedAt != null) PinnedManualPlaylist(entry),
    for (final playlist in smart)
      if (playlist.pinnedAt != null) PinnedSmartPlaylist(playlist),
  ]..sort((a, b) => a.pinnedAt.compareTo(b.pinnedAt));
});

// ---------------------------------------------------------------------------
// Track picker
// ---------------------------------------------------------------------------

/// The whole library, unfiltered, for the track picker.
///
/// The picker searches and groups in memory rather than re-querying. Its
/// search box is its own — routing it through the library's search state would
/// retype the Library tab underneath — and the album and artist tabs have to
/// stay consistent with the exact track list they were grouped from, which is
/// only guaranteed when all three read one snapshot.
final pickerLibraryProvider = StreamProvider.family<List<Track>, LibrarySort>((
  ref,
  sort,
) {
  return ref.watch(databaseProvider).watchLibrary(sort: sort);
});
