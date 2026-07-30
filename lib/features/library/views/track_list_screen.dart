import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/track_tile.dart';
import '../../player/providers/player_providers.dart';
import '../../settings/providers/settings_providers.dart';

/// Shared scaffold for every "a list of tracks with a header" screen: album,
/// artist, folder and smart-list details all differ only in what they watch.
class TrackListScreen extends ConsumerWidget {
  const TrackListScreen({
    super.key,
    required this.title,
    required this.tracks,
    this.subtitle,
    this.artPath,
    this.leadingIcon,
    this.showAlbumInRows = true,
  });

  final String title;
  final String? subtitle;
  final AsyncValue<List<Track>> tracks;
  final String? artPath;
  final IconData? leadingIcon;
  final bool showAlbumInRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingFilesProvider).value ?? const {};
    final controller = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No tracks here'));
          }

          final totalMs =
              list.fold<int>(0, (sum, track) => sum + track.durationMs);

          return Column(
            children: [
              _Header(
                title: title,
                subtitle: subtitle,
                artPath: artPath,
                leadingIcon: leadingIcon,
                trackCount: list.length,
                totalMs: totalMs,
                onPlay: () =>
                    controller.playFromList(list.first, list, title),
                onShuffle: () => controller.shufflePlayList(list, title),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final track = list[index];
                    return TrackTile(
                      track: track,
                      showAlbum: showAlbumInRows,
                      missing: missing.contains(track.id),
                      onTap: () =>
                          controller.playFromList(track, list, title),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.artPath,
    required this.leadingIcon,
    required this.trackCount,
    required this.totalMs,
    required this.onPlay,
    required this.onShuffle,
  });

  final String title;
  final String? subtitle;
  final String? artPath;
  final IconData? leadingIcon;
  final int trackCount;
  final int totalMs;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = '$trackCount track${trackCount == 1 ? '' : 's'} · '
        '${formatDurationMs(totalMs)}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (leadingIcon != null)
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(leadingIcon,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
            )
          else
            ArtThumb(artPath: artPath, size: 96, borderRadius: 12),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: const Text('Play'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onShuffle,
                      icon: const Icon(Icons.shuffle, size: 20),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
