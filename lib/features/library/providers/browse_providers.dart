import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import 'library_providers.dart';

/// Albums and artists honour the library search box, so typing filters every
/// browse tab at once.
final albumsProvider = StreamProvider<List<AlbumSummary>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAlbums(search: ref.watch(librarySearchProvider));
});

final artistsProvider = StreamProvider<List<ArtistSummary>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchArtists(search: ref.watch(librarySearchProvider));
});

final foldersProvider = StreamProvider<List<FolderSummary>>((ref) {
  return ref.watch(databaseProvider).watchFolders();
});

final albumTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, album) {
  return ref.watch(databaseProvider).watchAlbumTracks(album);
});

final artistTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, artist) {
  return ref.watch(databaseProvider).watchArtistTracks(artist);
});

final artistAlbumsProvider =
    StreamProvider.family<List<AlbumSummary>, String>((ref, artist) {
  return ref.watch(databaseProvider).watchArtistAlbums(artist);
});

final folderTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, folder) {
  return ref.watch(databaseProvider).watchFolderTracks(folder);
});

// ---------------------------------------------------------------------------
// Smart lists
// ---------------------------------------------------------------------------

enum SmartList { favorites, recentlyAdded, recentlyPlayed, mostPlayed }

extension SmartListLabel on SmartList {
  String get label => switch (this) {
        SmartList.favorites => 'Favorites',
        SmartList.recentlyAdded => 'Recently added',
        SmartList.recentlyPlayed => 'Recently played',
        SmartList.mostPlayed => 'Most played',
      };
}

final smartListProvider =
    StreamProvider.family<List<Track>, SmartList>((ref, list) {
  final db = ref.watch(databaseProvider);
  return switch (list) {
    SmartList.favorites => db.watchFavorites(),
    SmartList.recentlyAdded => db.watchRecentlyAdded(),
    SmartList.recentlyPlayed => db.watchRecentlyPlayed(),
    SmartList.mostPlayed => db.watchMostPlayed(),
  };
});

/// Live row for a single track id.
final trackStreamProvider =
    StreamProvider.family<Track?, int>((ref, id) {
  return ref.watch(databaseProvider).watchTrackById(id);
});

/// Soft-deleted tracks, shown in the trash screen.
final deletedTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(databaseProvider).watchDeletedTracks();
});
