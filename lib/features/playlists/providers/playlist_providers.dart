import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

final playlistsProvider = StreamProvider<List<PlaylistWithCount>>((ref) {
  return ref.watch(databaseProvider).watchPlaylists();
});

final playlistProvider =
    StreamProvider.family<Playlist?, int>((ref, playlistId) {
  return ref.watch(databaseProvider).watchPlaylist(playlistId);
});

final playlistTracksProvider =
    StreamProvider.family<List<Track>, int>((ref, playlistId) {
  return ref.watch(databaseProvider).watchPlaylistTracks(playlistId);
});
