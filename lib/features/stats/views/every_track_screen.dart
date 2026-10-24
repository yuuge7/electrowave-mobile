import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../providers/track_stats_providers.dart';
import '../widgets/stat_rank_row.dart';

/// Every track in the library with its all-time figures, unplayed ones
/// included. The Stats tab shows the top ten; this is the rest of the table,
/// and the way into any one track's own record.
class EveryTrackScreen extends ConsumerStatefulWidget {
  const EveryTrackScreen({super.key});

  @override
  ConsumerState<EveryTrackScreen> createState() => _EveryTrackScreenState();
}

class _EveryTrackScreenState extends ConsumerState<EveryTrackScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(everyTrackSortProvider);
    final rowsAsync = ref.watch(everyTrackSortedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Every track'),
        actions: [
          PopupMenuButton<TrackStatsSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort tracks',
            initialValue: sort,
            onSelected: (value) =>
                ref.read(everyTrackSortProvider.notifier).state = value,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: TrackStatsSort.heard,
                child: Text('Time heard'),
              ),
              PopupMenuItem(value: TrackStatsSort.plays, child: Text('Plays')),
              PopupMenuItem(
                value: TrackStatsSort.recent,
                child: Text('Last played'),
              ),
              PopupMenuItem(value: TrackStatsSort.title, child: Text('Title')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search title, artist, album',
              leading: const Icon(Icons.search),
              trailing: [
                if (_search.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _search = '');
                    },
                  ),
              ],
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
        ),
      ),
      body: AsyncView<List<TrackTotals>>(
        value: rowsAsync,
        data: (sorted) {
          if (sorted.isEmpty) {
            return const EmptyStateView(
              icon: Icons.library_music_outlined,
              title: 'No tracks yet',
              message: 'Add music from the Library tab and its figures will '
                  'show up here.',
            );
          }
          // Already in order; narrowing keeps that order.
          final rows = _search.trim().isEmpty
              ? sorted
              : sortTrackTotals(sorted, sort, search: _search);
          if (rows.isEmpty) {
            return EmptyStateView(
              icon: Icons.search_off,
              title: 'No matches',
              message: 'Nothing in the library matches "${_search.trim()}".',
            );
          }
          return _TrackTable(rows: rows, sort: sort);
        },
      ),
    );
  }
}

class _TrackTable extends StatelessWidget {
  const _TrackTable({required this.rows, required this.sort});

  final List<TrackTotals> rows;
  final TrackStatsSort sort;

  @override
  Widget build(BuildContext context) {
    final byPlays = sort == TrackStatsSort.plays;
    final ranked = sort == TrackStatsSort.heard || byPlays;
    var maxValue = 0;
    var played = 0;
    for (final row in rows) {
      final value = byPlays ? row.plays : row.listenedMs;
      if (value > maxValue) maxValue = value;
      if (!row.untouched) played++;
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '${rows.length} track${rows.length == 1 ? '' : 's'}, '
              '$played played · all time. Tap one for its full record.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final row = rows[index - 1];
        final track = row.track;
        final lastPlayed = track.lastPlayed;

        return StatRankRow(
          rank: ranked ? index : null,
          title: track.title,
          subtitle: sort == TrackStatsSort.recent && lastPlayed != null
              ? '${track.artist} · ${DateFormat.yMMMd().format(lastPlayed)}'
              : track.artist,
          artPath: track.albumArtPath,
          seed: track.album.isNotEmpty ? track.album : track.title,
          value: (byPlays ? row.plays : row.listenedMs).toDouble(),
          maxValue: maxValue.toDouble(),
          primary: row.untouched
              ? 'Unplayed'
              : '${row.plays} play${row.plays == 1 ? '' : 's'}',
          secondary: row.listenedMs > 0
              ? '${formatListeningTime(
                  Duration(milliseconds: row.listenedMs),
                )} heard'
              : null,
          onTap: () => context.push('/track/${track.id}/stats'),
          onLongPress: () =>
              showTrackContextMenu(context, track, showStats: false),
        );
      },
    );
  }
}
