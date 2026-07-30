import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../features/player/providers/player_providers.dart';
import '../utils/format.dart';
import 'art_thumb.dart';
import 'track_context_menu.dart';

/// Standard track row used in library, playlists, search results.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.showAlbum = true,
    this.missing = false,
    this.trailingExtra,
  });

  final Track track;
  final VoidCallback onTap;
  final bool showAlbum;

  /// File no longer exists on disk (flagged after backup import).
  final bool missing;

  final Widget? trailingExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(
        playerControllerProvider.select((s) => s.current?.id == track.id));

    final subtitle = showAlbum && track.album.isNotEmpty
        ? '${track.artist} · ${track.album}'
        : track.artist;

    return ListTile(
      onTap: missing
          ? () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
                SnackBar(content: Text('File missing: ${track.filePath}')))
          : onTap,
      onLongPress: () => showTrackContextMenu(context, track),
      leading: ArtThumb(artPath: track.albumArtPath),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: current
            ? TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: Row(
        children: [
          if (missing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.error_outline,
                  size: 14, color: theme.colorScheme.error),
            ),
          Expanded(
            child: Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatDurationMs(track.durationMs),
              style: theme.textTheme.bodySmall),
          ?trailingExtra,
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showTrackContextMenu(context, track),
          ),
        ],
      ),
    );
  }
}
