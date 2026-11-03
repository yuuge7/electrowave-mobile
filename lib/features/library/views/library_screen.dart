import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../player/providers/player_providers.dart';
import '../../playlists/providers/playlist_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/track_tile.dart';
import '../providers/browse_providers.dart';
import '../providers/library_providers.dart';
import 'browse_views.dart';
import '../widgets/bulk_actions.dart';
import '../../../shared/widgets/alphabet_list.dart';
import 'track_list_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final TabController _tabController = TabController(
    length: 6,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    final ok = await ref
        .read(scanControllerProvider.notifier)
        .pickAndScanFolder();
    if (!ok && mounted) context.push('/permission');
  }

  Future<void> _addFiles() async {
    final ok = await ref
        .read(scanControllerProvider.notifier)
        .pickAndScanFiles();
    if (!ok && mounted) context.push('/permission');
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final sort = ref.watch(librarySortProvider);
    final scan = ref.watch(scanControllerProvider);
    final missing = ref.watch(missingFilesProvider).value ?? const {};
    // The field's text lives in the provider, so the clear button and the
    // "no results" copy both react without a local setState.
    final searching = ref.watch(librarySearchInputProvider).isNotEmpty;

    ref.listen(scanControllerProvider, (previous, current) {
      final message = current.message;
      if (message != null && previous?.message != message) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        ref.read(scanControllerProvider.notifier).clearMessage();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Reverse sort direction',
            icon: Icon(
              ref.watch(libraryDescendingProvider) ? Icons.south : Icons.north,
            ),
            onPressed: () =>
                ref.read(libraryDescendingProvider.notifier).state = !ref.read(
                  libraryDescendingProvider,
                ),
          ),
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort library',
            initialValue: sort,
            onSelected: (value) =>
                ref.read(librarySortProvider.notifier).state = value,
            itemBuilder: (context) => const [
              PopupMenuItem(value: LibrarySort.title, child: Text('Title')),
              PopupMenuItem(value: LibrarySort.artist, child: Text('Artist')),
              PopupMenuItem(
                value: LibrarySort.dateAdded,
                child: Text('Date added'),
              ),
              PopupMenuItem(
                value: LibrarySort.playCount,
                child: Text('Play count'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: 'Add music',
            onSelected: (value) =>
                value == 'folder' ? _addFolder() : _addFiles(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'folder', child: Text('Scan folder')),
              PopupMenuItem(value: 'files', child: Text('Pick files')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Search title, artist, album',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (searching)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          ref.read(librarySearchInputProvider.notifier).state =
                              '';
                        },
                      ),
                  ],
                  onChanged: (value) =>
                      ref.read(librarySearchInputProvider.notifier).state =
                          value,
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Tracks'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Folders'),
                  Tab(text: 'Genres'),
                  Tab(text: 'Years'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (scan.running)
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text('Scanning ${scan.processed}/${scan.total}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scan.folder ?? 'Finding files',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  LinearProgressIndicator(
                    value: scan.total > 0 ? scan.processed / scan.total : null,
                  ),
                ],
              ),
              trailing: TextButton(
                onPressed: ref.read(scanControllerProvider.notifier).cancel,
                child: const Text('Cancel'),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TracksTab(
                  tracksAsync: tracksAsync,
                  missing: missing,
                  searching: searching,
                  onAddFolder: _addFolder,
                  onAddFiles: _addFiles,
                ),
                const AlbumsGrid(),
                const ArtistsList(),
                const FoldersList(),
                const MetadataBrowse(years: false),
                const MetadataBrowse(years: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat track list, with the shortcut row — pinned playlists, then the
/// built-in smart lists — fixed above it.
class _TracksTab extends ConsumerWidget {
  const _TracksTab({
    required this.tracksAsync,
    required this.missing,
    required this.searching,
    required this.onAddFolder,
    required this.onAddFiles,
  });

  final AsyncValue<List<Track>> tracksAsync;
  final Set<int> missing;
  final bool searching;
  final VoidCallback onAddFolder;
  final VoidCallback onAddFiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: tracksAsync,
      onRetry: () => ref.invalidate(libraryTracksProvider),
      data: (tracks) {
        if (tracks.isEmpty) {
          return _EmptyLibrary(
            searching: searching,
            onAddFolder: onAddFolder,
            onAddFiles: onAddFiles,
          );
        }
        return Column(
          children: [
            if (ref.watch(librarySelectionProvider).isNotEmpty)
              BulkActions(tracks: tracks)
            else
              const _ShortcutsRow(),
            const Divider(height: 1),
            Expanded(
              child: AlphabetList(
                showRail: ref.watch(librarySortProvider) == LibrarySort.title,
                labels: tracks.map((t) => t.title).toList(),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    selected: ref
                        .watch(librarySelectionProvider)
                        .contains(track.id),
                    onLongPress: () =>
                        ref.read(librarySelectionProvider.notifier).state = {
                          ...ref.read(librarySelectionProvider),
                          track.id,
                        },
                    missing: missing.contains(track.id),
                    onTap: () {
                      final ids = ref.read(librarySelectionProvider);
                      if (ids.isNotEmpty) {
                        final next = {...ids};
                        if (!next.add(track.id)) next.remove(track.id);
                        ref.read(librarySelectionProvider.notifier).state =
                            next;
                      } else {
                        ref
                            .read(playerControllerProvider.notifier)
                            .playFromList(track, tracks, 'Library');
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShortcutsRow extends ConsumerWidget {
  const _ShortcutsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedPlaylistsProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          // Pinned first: the built-in chips alone are wider than a phone,
          // and a list someone chose to pin shouldn't start offscreen.
          for (final playlist in pinned)
            ActionChip(
              avatar: const Icon(Icons.push_pin_outlined, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // go, not push: the playlist lives in the Playlists tab, and
              // the nav bar should say so.
              onPressed: () => context.go(playlist.location),
            ),
          if (pinned.isNotEmpty)
            const SizedBox(height: 24, child: VerticalDivider(width: 1)),
          for (final list in SmartList.values)
            ActionChip(
              avatar: Icon(switch (list) {
                SmartList.favorites => Icons.favorite,
                SmartList.recentlyAdded => Icons.new_releases_outlined,
                SmartList.recentlyPlayed => Icons.history,
                SmartList.mostPlayed => Icons.trending_up,
              }, size: 18),
              label: Text(list.label),
              onPressed: () => context.push('/smart/${list.name}'),
            ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.searching,
    required this.onAddFolder,
    required this.onAddFiles,
  });

  final bool searching;
  final VoidCallback onAddFolder;
  final VoidCallback onAddFiles;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const EmptyStateView(
        icon: Icons.search_off,
        title: 'No matches',
        message:
            'Nothing in your library matches that title, artist or '
            'album. Try a shorter search.',
      );
    }
    return EmptyStateView(
      icon: Icons.library_music_outlined,
      title: 'Your library is empty',
      message:
          'Point Electrowave at the folder your music lives in. It reads '
          'tags and album art in place — nothing is copied or uploaded.',
      action: FilledButton.icon(
        onPressed: onAddFolder,
        icon: const Icon(Icons.folder_open),
        label: const Text('Scan a folder'),
      ),
      secondaryAction: TextButton.icon(
        onPressed: onAddFiles,
        icon: const Icon(Icons.audio_file),
        label: const Text('Pick individual files'),
      ),
    );
  }
}

class MetadataBrowse extends ConsumerWidget {
  const MetadataBrowse({super.key, required this.years});
  final bool years;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryTracksProvider).value ?? [];
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      final keys = years
          ? [
              t.year?.toString() ?? 'Unknown year',
              if (t.year != null) '${t.year! ~/ 10 * 10}s',
            ]
          : [t.genre ?? 'Unknown genre'];
      for (final key in keys) {
        groups.putIfAbsent(key, () => []).add(t);
      }
    }
    final keys = groups.keys.toList()..sort();
    if (keys.isEmpty) {
      return const Center(child: Text('Scan music to browse its tags'));
    }
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        return ListTile(
          leading: Icon(years ? Icons.calendar_today : Icons.style),
          title: Text(key),
          subtitle: Text('${groups[key]!.length} tracks'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TrackListScreen(
                title: key,
                tracks: AsyncValue.data(groups[key]!),
              ),
            ),
          ),
        );
      },
    );
  }
}
