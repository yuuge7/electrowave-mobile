import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../player/providers/player_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../../../shared/widgets/track_tile.dart';
import '../providers/browse_providers.dart';
import '../providers/library_providers.dart';
import 'browse_views.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    final ok =
        await ref.read(scanControllerProvider.notifier).pickAndScanFolder();
    if (!ok && mounted) context.push('/permission');
  }

  Future<void> _addFiles() async {
    final ok =
        await ref.read(scanControllerProvider.notifier).pickAndScanFiles();
    if (!ok && mounted) context.push('/permission');
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final sort = ref.watch(librarySortProvider);
    final scan = ref.watch(scanControllerProvider);
    final missing = ref.watch(missingFilesProvider).value ?? const {};

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
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: sort,
            onSelected: (value) =>
                ref.read(librarySortProvider.notifier).state = value,
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: LibrarySort.title, child: Text('Title')),
              PopupMenuItem(
                  value: LibrarySort.artist, child: Text('Artist')),
              PopupMenuItem(
                  value: LibrarySort.dateAdded, child: Text('Date added')),
              PopupMenuItem(
                  value: LibrarySort.playCount, child: Text('Play count')),
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
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(librarySearchProvider.notifier).state = '';
                          setState(() {});
                        },
                      ),
                  ],
                  onChanged: (value) {
                    ref.read(librarySearchProvider.notifier).state = value;
                    setState(() {});
                  },
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Tracks'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Folders'),
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
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Scanning… ${scan.processed}/${scan.total}'),
              dense: true,
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TracksTab(
                  tracksAsync: tracksAsync,
                  missing: missing,
                  searching: _searchController.text.isNotEmpty,
                  onAddFolder: _addFolder,
                  onAddFiles: _addFiles,
                ),
                const AlbumsGrid(),
                const ArtistsList(),
                const FoldersList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat track list, with the smart-list shortcuts pinned above it.
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
    return tracksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
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
            const _SmartListsRow(),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    missing: missing.contains(track.id),
                    onTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playFromList(track, tracks, 'Library'),
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

class _SmartListsRow extends StatelessWidget {
  const _SmartListsRow();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          for (final list in SmartList.values)
            ActionChip(
              avatar: Icon(
                switch (list) {
                  SmartList.favorites => Icons.favorite,
                  SmartList.recentlyAdded => Icons.new_releases_outlined,
                  SmartList.recentlyPlayed => Icons.history,
                  SmartList.mostPlayed => Icons.trending_up,
                },
                size: 18,
              ),
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
      return const Center(child: Text('No tracks match your search'));
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('Your library is empty',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Scan a folder to add your music'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAddFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Scan folder'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAddFiles,
            icon: const Icon(Icons.audio_file),
            label: const Text('Pick individual files'),
          ),
        ],
      ),
    );
  }
}
