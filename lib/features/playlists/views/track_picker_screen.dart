import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart' as type;
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../../shared/widgets/state_views.dart';
import '../../player/providers/player_providers.dart';
import '../providers/playlist_providers.dart';

/// Pick many tracks at once, then commit them to a playlist in one write.
///
/// Adding tracks used to be a one-at-a-time trip through the track menu, which
/// is fine for an afterthought and useless for building a forty-track list.
/// This is the same library in selection mode: tap a row to take it, hold to
/// take everything between it and the last one, or take a whole album or
/// artist from the tabs beside it.
///
/// [playlistId] null means the playlist does not exist yet — the app bar
/// carries the name field, and committing creates it.
class TrackPickerScreen extends ConsumerStatefulWidget {
  const TrackPickerScreen({super.key, this.playlistId});

  final int? playlistId;

  @override
  ConsumerState<TrackPickerScreen> createState() => _TrackPickerScreenState();
}

class _TrackPickerScreenState extends ConsumerState<TrackPickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();

  /// Picked track ids. A plain set is insertion-ordered in Dart, and that
  /// order is what the playlist ends up in — the list reads back the way it
  /// was built rather than in library order.
  final _selected = <int>{};

  String _query = '';
  LibrarySort _sort = LibrarySort.artist;

  /// Row the last plain tap landed on, so a long-press knows which run to
  /// take. Cleared whenever the visible list changes underneath it.
  int? _anchor;

  /// Tracks already on the playlist are shown for context rather than hidden,
  /// until a long list makes that noise instead of context.
  bool _hideExisting = false;

  bool _saving = false;

  bool get _isNew => widget.playlistId == null;

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  void _toggle(int trackId, {int? index}) {
    setState(() {
      if (!_selected.remove(trackId)) _selected.add(trackId);
      _anchor = index;
    });
    HapticFeedback.selectionClick();
  }

  /// Long-press: take everything between the last tapped row and this one.
  void _extendTo(int index, List<Track> visible, Set<int> existing) {
    final anchor = _anchor;
    if (anchor == null || anchor == index) {
      _toggle(visible[index].id, index: index);
      return;
    }
    final from = anchor < index ? anchor : index;
    final to = anchor < index ? index : anchor;
    setState(() {
      for (var i = from; i <= to; i++) {
        final id = visible[i].id;
        if (!existing.contains(id)) _selected.add(id);
      }
      _anchor = index;
    });
    HapticFeedback.mediumImpact();
  }

  void _setGroup(List<Track> tracks, Set<int> existing, {required bool add}) {
    setState(() {
      for (final track in tracks) {
        if (existing.contains(track.id)) continue;
        if (add) {
          _selected.add(track.id);
        } else {
          _selected.remove(track.id);
        }
      }
      _anchor = null;
    });
    HapticFeedback.selectionClick();
  }

  // -------------------------------------------------------------------------
  // Commit
  // -------------------------------------------------------------------------

  Future<void> _commit() async {
    if (_selected.isEmpty || _saving) return;
    final ids = _selected.toList();
    final db = ref.read(databaseProvider);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final playlistId = widget.playlistId;
    if (playlistId == null) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Give the playlist a name')),
          );
        return;
      }
      setState(() => _saving = true);
      final int id;
      try {
        id = await db.createPlaylistWithTracks(name, ids);
      } catch (_) {
        // A failed write must not leave the button spinning forever with the
        // selection stranded behind it.
        if (mounted) setState(() => _saving = false);
        rethrow;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Created "$name" with ${_countLabel(ids.length)}'),
          ),
        );
      // `go` rather than a pop: it rebuilds the stack at the new playlist,
      // which drops this screen and lands on the thing just made.
      router.go('/playlists/$id');
      return;
    }

    setState(() => _saving = true);
    final int added;
    try {
      added = await db.addTracksToPlaylist(playlistId, ids);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Added ${_countLabel(added)}')));
    router.pop();
  }

  Future<bool> _confirmDiscard() async {
    if (_selected.isEmpty || _saving) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave without adding?'),
        content: Text(
          '${_countLabel(_selected.length)} picked. '
          'Leaving loses the selection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep picking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  List<Track> _filter(List<Track> tracks, Set<int> existing) {
    final needle = _query.trim().toLowerCase();
    return [
      for (final track in tracks)
        if (!(_hideExisting && existing.contains(track.id)) &&
            (needle.isEmpty ||
                track.title.toLowerCase().contains(needle) ||
                track.artist.toLowerCase().contains(needle) ||
                track.album.toLowerCase().contains(needle)))
          track,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(pickerLibraryProvider(_sort));
    final playlistId = widget.playlistId;
    final existing = playlistId == null
        ? const <int>{}
        : {
            for (final track
                in ref.watch(playlistTracksProvider(playlistId)).value ??
                    const <Track>[])
              track.id,
          };
    final playlistName = playlistId == null
        ? null
        : ref.watch(playlistProvider(playlistId)).value?.name;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isNew
              ? TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context).textTheme.titleLarge,
                  decoration: const InputDecoration(
                    hintText: 'Playlist name',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                )
              : Text(
                  playlistName == null ? 'Add tracks' : 'Add to $playlistName',
                ),
          actions: [
            PopupMenuButton<LibrarySort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort tracks',
              initialValue: _sort,
              onSelected: (value) => setState(() {
                _sort = value;
                _anchor = null;
              }),
              itemBuilder: (context) => const [
                PopupMenuItem(value: LibrarySort.artist, child: Text('Artist')),
                PopupMenuItem(value: LibrarySort.title, child: Text('Title')),
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
              tooltip: 'More picking options',
              onSelected: (value) {
                switch (value) {
                  case 'all':
                    _setGroup(
                      _filter(libraryAsync.value ?? const <Track>[], existing),
                      existing,
                      add: true,
                    );
                  case 'none':
                    setState(() {
                      _selected.clear();
                      _anchor = null;
                    });
                  case 'hide':
                    setState(() {
                      _hideExisting = !_hideExisting;
                      _anchor = null;
                    });
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('Select all shown'),
                ),
                const PopupMenuItem(
                  value: 'none',
                  child: Text('Clear selection'),
                ),
                if (!_isNew)
                  PopupMenuItem(
                    value: 'hide',
                    child: Text(
                      _hideExisting
                          ? 'Show tracks already in the list'
                          : 'Hide tracks already in the list',
                    ),
                  ),
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
                      if (_query.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _anchor = null;
                            });
                          },
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _query = value;
                      _anchor = null;
                    }),
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Tracks'),
                    Tab(text: 'Albums'),
                    Tab(text: 'Artists'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: AsyncView<List<Track>>(
          value: libraryAsync,
          onRetry: () => ref.invalidate(pickerLibraryProvider(_sort)),
          data: (library) {
            final visible = _filter(library, existing);
            final picked = [
              for (final track in library)
                if (_selected.contains(track.id)) track,
            ];
            return Column(
              children: [
                Expanded(
                  child: visible.isEmpty
                      ? _emptyList(library.isEmpty)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _TrackList(
                              tracks: visible,
                              selected: _selected,
                              existing: existing,
                              onTap: (index) =>
                                  _toggle(visible[index].id, index: index),
                              onExtend: (index) =>
                                  _extendTo(index, visible, existing),
                              previewContextName: playlistName == null
                                  ? 'Picking tracks'
                                  : 'Adding to $playlistName',
                            ),
                            _GroupList(
                              groups: _groupBy(
                                visible,
                                (track) => track.album,
                                'Unknown album',
                              ),
                              selected: _selected,
                              existing: existing,
                              kind: _GroupKind.album,
                              onToggle: (tracks, add) =>
                                  _setGroup(tracks, existing, add: add),
                            ),
                            _GroupList(
                              groups: _groupBy(
                                visible,
                                (track) => track.artist,
                                'Unknown artist',
                              ),
                              selected: _selected,
                              existing: existing,
                              kind: _GroupKind.artist,
                              onToggle: (tracks, add) =>
                                  _setGroup(tracks, existing, add: add),
                            ),
                          ],
                        ),
                ),
                _TallyBar(
                  picked: picked,
                  saving: _saving,
                  actionLabel: _isNew ? 'Create' : 'Add',
                  onClear: picked.isEmpty
                      ? null
                      : () => setState(() {
                          _selected.clear();
                          _anchor = null;
                        }),
                  onCommit: _commit,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyList(bool libraryEmpty) {
    if (libraryEmpty) {
      return const EmptyStateView(
        icon: Icons.library_music_outlined,
        title: 'Nothing to pick from',
        message: 'Scan a folder from the Library tab first, then come back and '
            'build the list.',
      );
    }
    if (_hideExisting) {
      return EmptyStateView(
        icon: Icons.playlist_add_check,
        title: 'Everything here is already in',
        message: 'No track matching this search is missing from the list.',
        action: TextButton(
          onPressed: () => setState(() => _hideExisting = false),
          child: const Text('Show tracks already in the list'),
        ),
      );
    }
    return const EmptyStateView(
      icon: Icons.search_off,
      title: 'No matches',
      message: 'Nothing in your library matches that title, artist or album. '
          'Try a shorter search.',
    );
  }
}

// ---------------------------------------------------------------------------
// Grouping
// ---------------------------------------------------------------------------

class _Group {
  const _Group({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;

  String get artist {
    final names = {
      for (final track in tracks)
        if (track.artist.isNotEmpty) track.artist,
    };
    if (names.isEmpty) return 'Unknown artist';
    return names.length == 1 ? names.first : 'Various artists';
  }

  String? get artPath {
    for (final track in tracks) {
      final path = track.albumArtPath;
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
  }
}

/// Groups are built from the same filtered list the Tracks tab shows, so a
/// search narrows an album to the tracks that matched rather than hiding it.
List<_Group> _groupBy(
  List<Track> tracks,
  String Function(Track) key,
  String fallback,
) {
  final buckets = <String, List<Track>>{};
  for (final track in tracks) {
    final name = key(track).trim();
    buckets.putIfAbsent(name.isEmpty ? fallback : name, () => []).add(track);
  }
  final names = buckets.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [for (final name in names) _Group(name: name, tracks: buckets[name]!)];
}

// ---------------------------------------------------------------------------
// Track rows
// ---------------------------------------------------------------------------

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.selected,
    required this.existing,
    required this.onTap,
    required this.onExtend,
    required this.previewContextName,
  });

  final List<Track> tracks;
  final Set<int> selected;
  final Set<int> existing;
  final void Function(int index) onTap;
  final void Function(int index) onExtend;

  /// What the player calls the context a preview starts, so "Playing from"
  /// says where the sound came from once you leave the picker.
  final String previewContextName;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _PickingHint(
            'Tap to pick · hold for a run · play to hear it',
          );
        }
        final row = index - 1;
        final track = tracks[row];
        final alreadyIn = existing.contains(track.id);
        final isSelected = selected.contains(track.id);
        return _PickRow(
          selected: isSelected,
          disabled: alreadyIn,
          onTap: alreadyIn ? null : () => onTap(row),
          onLongPress: alreadyIn ? null : () => onExtend(row),
          semanticLabel: '${track.title}, ${track.artist}',
          leading: _PickThumb(
            artPath: track.albumArtPath,
            seed: track.album.isNotEmpty ? track.album : track.title,
            selected: isSelected,
          ),
          title: track.title,
          subtitle: track.album.isEmpty
              ? track.artist
              : '${track.artist} · ${track.album}',
          trailing: alreadyIn
              ? const PanelLabel('In list')
              : Text(
                  formatDurationMs(track.durationMs),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          // Deliberately outside the row's own semantics and outside the
          // dimming a track already in the list gets: hearing a track is
          // never disabled, including for the ones you cannot pick again.
          action: _PreviewButton(
            track: track,
            contextTracks: tracks,
            contextName: previewContextName,
          ),
        );
      },
    );
  }
}

/// Hear a row before committing to it.
///
/// A title and an artist are not enough to know what a track is, and the
/// answer used to mean leaving the picker — which threw the selection away.
/// This plays it through the real player, so the picker list becomes the
/// playback context and the transport keeps working while you carry on
/// picking.
class _PreviewButton extends ConsumerWidget {
  const _PreviewButton({
    required this.track,
    required this.contextTracks,
    required this.contextName,
  });

  final Track track;
  final List<Track> contextTracks;
  final String contextName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(
      playerControllerProvider.select((s) => s.current?.id == track.id),
    );
    final playing =
        isCurrent && (ref.watch(playingProvider).value ?? false);
    final tokens = context.deck;

    return IconButton(
      icon: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      ),
      iconSize: 22,
      color: isCurrent
          ? tokens.signal
          : Theme.of(context).colorScheme.onSurfaceVariant,
      tooltip: playing ? 'Pause' : 'Hear ${track.title}',
      onPressed: () {
        final controller = ref.read(playerControllerProvider.notifier);
        if (isCurrent) {
          controller.togglePlayPause();
        } else {
          controller.playFromList(track, contextTracks, contextName);
        }
      },
    );
  }
}

/// Range-select is what makes a fifty-track list bearable, and a long-press is
/// invisible until something says it is there.
class _PickingHint extends StatelessWidget {
  const _PickingHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: PanelLabel(text),
    );
  }
}

/// One selectable row.
///
/// There is no checkbox in here. This app says live state in teal — the
/// playing track, the position inside it, the destination you are on — and a
/// picked track is live state, so it is marked the same way: the 2px rule on
/// the leading edge, and the thumbnail taken over by the signal colour.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.onLongPress,
    required this.semanticLabel,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.action,
  });

  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String semanticLabel;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;

  /// A control that belongs to the row but is not part of picking it. It sits
  /// outside the tile so that neither the row's `excludeSemantics` nor the
  /// dimming of an already-added track reaches it.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signal = context.deck.signal;

    final row = Opacity(
      opacity: disabled ? 0.45 : 1,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        selected: selected,
        selectedTileColor: signal.withValues(alpha: 0.07),
        selectedColor: theme.colorScheme.onSurface,
        leading: leading,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing,
      ),
    );

    final tile = Semantics(
      checked: selected,
      enabled: !disabled,
      label: semanticLabel,
      hint: disabled ? 'Already in the playlist' : 'Pick for the playlist',
      excludeSemantics: true,
      child: row,
    );

    return Stack(
      children: [
        if (action == null)
          tile
        else
          Row(
            children: [
              Expanded(child: tile),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: action,
              ),
            ],
          ),
        if (selected)
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            width: 2,
            child: ColoredBox(color: signal),
          ),
      ],
    );
  }
}

/// Album art that takes the signal colour once its track is picked.
class _PickThumb extends StatelessWidget {
  const _PickThumb({
    required this.artPath,
    required this.seed,
    required this.selected,
    this.fraction,
  });

  final String? artPath;
  final String seed;
  final bool selected;

  /// Group tiles only: how much of the group is picked, drawn as the same
  /// filling rule the player uses for playback position. Null for a single
  /// track, which is either picked or not.
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final partial = fraction != null && fraction! > 0 && !selected;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ArtThumb(artPath: artPath, seed: seed),
          if (selected)
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.signal.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check, size: 24, color: tokens.onSignal),
            ),
          if (partial)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SignalRule(
                value: fraction,
                height: 4,
                trackColor: Colors.black.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Album / artist rows
// ---------------------------------------------------------------------------

enum _GroupKind { album, artist }

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.selected,
    required this.existing,
    required this.kind,
    required this.onToggle,
  });

  final List<_Group> groups;
  final Set<int> selected;
  final Set<int> existing;
  final _GroupKind kind;
  final void Function(List<Track> tracks, bool add) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: groups.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _PickingHint(
            kind == _GroupKind.album
                ? 'Tap an album to take all of it'
                : 'Tap an artist to take everything they are on',
          );
        }
        final group = groups[index - 1];
        final takeable = [
          for (final track in group.tracks)
            if (!existing.contains(track.id)) track,
        ];
        final picked = takeable
            .where((track) => selected.contains(track.id))
            .length;
        final all = takeable.isNotEmpty && picked == takeable.length;

        return _PickRow(
          selected: all,
          disabled: takeable.isEmpty,
          onTap: takeable.isEmpty ? null : () => onToggle(group.tracks, !all),
          onLongPress: null,
          semanticLabel:
              '${group.name}, $picked of ${takeable.length} tracks picked',
          leading: _PickThumb(
            artPath: kind == _GroupKind.album ? group.artPath : null,
            seed: group.name,
            selected: all,
            fraction: takeable.isEmpty ? null : picked / takeable.length,
          ),
          title: group.name,
          subtitle: kind == _GroupKind.album
              ? '${group.artist} · ${_countLabel(group.tracks.length)}'
              : _countLabel(group.tracks.length),
          trailing: takeable.isEmpty
              ? const PanelLabel('In list')
              : picked == 0
                  ? null
                  : PanelLabel('$picked/${takeable.length}'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tally bar
// ---------------------------------------------------------------------------

/// What is in hand, in the deck's own readout: the count large, the runtime
/// small beside it, the way the transport counter sets elapsed against total.
class _TallyBar extends StatelessWidget {
  const _TallyBar({
    required this.picked,
    required this.saving,
    required this.actionLabel,
    required this.onClear,
    required this.onCommit,
  });

  final List<Track> picked;
  final bool saving;
  final String actionLabel;
  final VoidCallback? onClear;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.deck;
    final runtime = Duration(
      milliseconds: picked.fold(0, (sum, track) => sum + track.durationMs),
    );
    final empty = picked.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          // The buttons are the part that grows: a long label, a large text
          // scale, and the readout beside them gets squeezed to nothing — at
          // which point its label wraps one character per line and the bar
          // eats the list. Capping the action side and scaling it down inside
          // that cap is what keeps the readout readable at every size.
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PanelLabel(empty ? 'Nothing picked yet' : 'Picked'),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${picked.length}',
                                style: type.counter(30).copyWith(
                                      color: empty
                                          ? theme.colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.4)
                                          : tokens.signal,
                                    ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '/',
                                  style: type.counter(16, weight: 300).copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.45),
                                      ),
                                ),
                              ),
                              Text(
                                formatListeningTime(runtime),
                                style: type.counter(16, weight: 500).copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.58,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onClear != null)
                            TextButton(
                              onPressed: onClear,
                              child: const Text('Clear'),
                            ),
                          const SizedBox(width: 4),
                          FilledButton(
                            onPressed: empty || saving ? null : onCommit,
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(actionLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _countLabel(int count) => '$count track${count == 1 ? '' : 's'}';
