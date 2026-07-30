import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../providers/browse_providers.dart';
import 'track_list_screen.dart';

/// Albums tab: art grid. Tapping opens the album's track list.
class AlbumsGrid extends ConsumerWidget {
  const AlbumsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);

    return albums.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('No albums yet'));
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final album = list[index];
            return _AlbumCard(album: album);
          },
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/album/${Uri.encodeComponent(album.album)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fills the tile's art area instead of assuming a square: the grid
          // cell height varies with the column width, and a hard-coded square
          // overflows at narrow widths.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => ArtThumb(
                artPath: album.albumArtPath,
                size: double.infinity,
                decodeWidth: constraints.maxWidth,
                borderRadius: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(album.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
          Text(album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Artists tab.
class ArtistsList extends ConsumerWidget {
  const ArtistsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);

    return artists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('No artists yet'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final artist = list[index];
            return ListTile(
              leading: ArtThumb(artPath: artist.albumArtPath),
              title: Text(artist.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${artist.albumCount} album${artist.albumCount == 1 ? '' : 's'} · '
                '${artist.trackCount} track${artist.trackCount == 1 ? '' : 's'}',
              ),
              trailing: Text(formatDurationMs(artist.totalMs),
                  style: Theme.of(context).textTheme.bodySmall),
              onTap: () => context
                  .push('/artist/${Uri.encodeComponent(artist.artist)}'),
            );
          },
        );
      },
    );
  }
}

/// Folders tab: browse by directory instead of by metadata.
class FoldersList extends ConsumerWidget {
  const FoldersList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);

    return folders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('No folders yet'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final folder = list[index];
            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(folder.name.isEmpty ? folder.path : folder.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(folder.path,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text('${folder.trackCount}',
                  style: Theme.of(context).textTheme.bodySmall),
              onTap: () => context
                  .push('/folder/${Uri.encodeComponent(folder.path)}'),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Detail screens
// ---------------------------------------------------------------------------

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.album});

  final String album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(albumTracksProvider(album));
    final list = tracks.value;
    final artist = (list == null || list.isEmpty)
        ? null
        : (list.map((t) => t.artist).toSet().length > 1
            ? 'Various artists'
            : list.first.artist);

    return TrackListScreen(
      title: album,
      subtitle: artist,
      artPath: (list == null || list.isEmpty) ? null : list.first.albumArtPath,
      tracks: tracks,
      // Redundant inside a single album.
      showAlbumInRows: false,
    );
  }
}

class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artist});

  final String artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(artistTracksProvider(artist));
    final albums = ref.watch(artistAlbumsProvider(artist)).value ?? const [];
    final list = tracks.value;

    return TrackListScreen(
      title: artist,
      subtitle: albums.isEmpty
          ? null
          : '${albums.length} album${albums.length == 1 ? '' : 's'}',
      artPath: (list == null || list.isEmpty) ? null : list.first.albumArtPath,
      tracks: tracks,
    );
  }
}

class FolderDetailScreen extends ConsumerWidget {
  const FolderDetailScreen({super.key, required this.folderPath});

  final String folderPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackListScreen(
      title: folderPath.split(RegExp(r'[/\\]')).last,
      subtitle: folderPath,
      leadingIcon: Icons.folder,
      tracks: ref.watch(folderTracksProvider(folderPath)),
    );
  }
}

class SmartListScreen extends ConsumerWidget {
  const SmartListScreen({super.key, required this.list});

  final SmartList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackListScreen(
      title: list.label,
      leadingIcon: switch (list) {
        SmartList.favorites => Icons.favorite,
        SmartList.recentlyAdded => Icons.new_releases_outlined,
        SmartList.recentlyPlayed => Icons.history,
        SmartList.mostPlayed => Icons.trending_up,
      },
      tracks: ref.watch(smartListProvider(list)),
    );
  }
}
