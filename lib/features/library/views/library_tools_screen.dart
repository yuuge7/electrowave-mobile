import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../player/services/audio_analyzer.dart';
import '../../player/providers/player_providers.dart';
import '../providers/library_providers.dart';

final librarySummaryProvider = FutureProvider.autoDispose<Map<String, Object>>((
  ref,
) async {
  ref.watch(scanControllerProvider.select((s) => s.running));
  final db = ref.watch(databaseProvider);
  final tracks = await db.watchLibrary().first;
  final formats = <String, int>{};
  var size = 0, ms = 0;
  for (final t in tracks) {
    final ext = t.filePath.split('.').last.toUpperCase();
    formats.update(ext, (n) => n + 1, ifAbsent: () => 1);
    size += t.fileSize > 0
        ? t.fileSize
        : (await File(t.filePath).exists()
              ? await File(t.filePath).length()
              : 0);
    ms += t.durationMs;
  }
  return {'songs': tracks.length, 'bytes': size, 'ms': ms, 'formats': formats};
});

class LibraryToolsScreen extends ConsumerStatefulWidget {
  const LibraryToolsScreen({super.key, required this.duplicates});
  final bool duplicates;
  @override
  ConsumerState<LibraryToolsScreen> createState() => _LibraryToolsScreenState();
}

class _LibraryToolsScreenState extends ConsumerState<LibraryToolsScreen> {
  bool running = false, cancelled = false;
  String status = '';
  List<List<Track>> groups = [];
  List<List<String>> copies = [];
  @override
  void dispose() {
    cancelled = true;
    super.dispose();
  }

  Future<void> run() async {
    setState(() {
      running = true;
      cancelled = false;
      status = 'Reading library…';
    });
    try {
      final db = ref.read(databaseProvider);
      final tracks = await db.watchLibrary().first;
      if (!mounted) return;
      if (widget.duplicates) {
        final byTags = <String, List<Track>>{};
        for (final t in tracks) {
          final key =
              '${t.title.toLowerCase()}|${t.artist.toLowerCase()}|${t.durationMs ~/ 2000}';
          byTags.putIfAbsent(key, () => []).add(t);
        }
        groups = byTags.values.where((g) => g.length > 1).toList();
        // Also inspect files folded into one library song, without altering them.
        final sizes = <int, List<String>>{};
        final scanner = ref.read(libraryScannerProvider);
        final paths = <String>{...tracks.map((t) => t.filePath)};
        for (final folder in ref.read(libraryFoldersProvider)) {
          paths.addAll(
            await scanner.collectAudioFiles(folder, cancelled: () => cancelled),
          );
        }
        for (final path in paths) {
          if (cancelled) break;
          try {
            final size = await File(path).length();
            sizes.putIfAbsent(size, () => []).add(path);
          } catch (_) {}
        }
        final found = <List<String>>[];
        for (final candidates in sizes.values.where((v) => v.length > 1)) {
          if (cancelled) break;
          final hashes = <int, List<String>>{};
          for (final path in candidates) {
            // Streaming fingerprint narrows candidates; byte comparison confirms.
            var hash = 2166136261;
            await for (final chunk in File(path).openRead()) {
              for (final b in chunk) {
                hash = ((hash ^ b) * 16777619) & 0xffffffff;
              }
              if (cancelled) break;
            }
            hashes.putIfAbsent(hash, () => []).add(path);
          }
          for (final collision in hashes.values.where((v) => v.length > 1)) {
            final verified = <String>[collision.first];
            for (final candidate in collision.skip(1)) {
              final left = await File(collision.first).open();
              final right = await File(candidate).open();
              var equal = true;
              try {
                while (equal) {
                  final a = await left.read(65536), b = await right.read(65536);
                  if (a.length != b.length) {
                    equal = false;
                    break;
                  }
                  if (a.isEmpty) break;
                  for (var i = 0; i < a.length; i++) {
                    if (a[i] != b[i]) {
                      equal = false;
                      break;
                    }
                  }
                }
              } finally {
                await left.close();
                await right.close();
              }
              if (equal) verified.add(candidate);
            }
            if (verified.length > 1) found.add(verified);
          }
          if (mounted) {
            setState(() => status = 'Checking ${paths.length} files…');
          }
        }
        copies = found;
        status = cancelled
            ? 'Cancelled'
            : '${groups.length} matching tag groups · ${copies.length} identical file groups';
      } else {
        final missing = tracks.where((t) => t.replayGainDb == null).toList();
        var completed = 0, failed = 0;
        for (final track in missing) {
          if (cancelled) break;
          if (mounted) {
            setState(
              () => status =
                  '${completed + 1}/${missing.length} · ${track.title}',
            );
          }
          try {
            final result = await AudioAnalyzer.analyze(track);
            await db.setCalculatedGain(track.id, result.gainDb);
            completed++;
          } catch (_) {
            failed++;
          }
        }
        status =
            '${cancelled ? 'Cancelled · ' : ''}$completed tracks analyzed${failed > 0 ? ' · $failed could not be decoded' : ''}';
      }
    } catch (e) {
      status = 'Could not finish: $e';
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.duplicates ? 'Duplicate finder' : 'Calculate ReplayGain',
      ),
    ),
    body: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4 + groups.length + copies.length,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(
            widget.duplicates
                ? 'Review matching tags and identical files. Removing a track only hides its library entry. Your music files stay on disk.'
                : 'Analyze audio on this phone at -18 LUFS, with a sample-peak limit. Calculated gains stay in the library and are included in backups; your music files are not changed.',
          );
        }
        if (index == 1) return const SizedBox(height: 16);
        if (index == 2) {
          return FilledButton(
            onPressed: running ? () => setState(() => cancelled = true) : run,
            child: Text(running ? 'Cancel' : 'Start'),
          );
        }
        if (index == 3) {
          return Column(
            children: [
              if (running) const LinearProgressIndicator(),
              Text(status),
            ],
          );
        }
        if (index < 4 + groups.length) {
          final group = groups[index - 4];
          return ExpansionTile(
            title: Text(group.first.title),
            subtitle: Text('${group.length} matching tracks'),
            children: [
              for (final t in group)
                ListTile(
                  title: Text(t.filePath),
                  trailing: IconButton(
                    tooltip: 'Hide this library entry',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      await ref.read(databaseProvider).softDeleteTrack(t.id);
                      ref
                          .read(playerControllerProvider.notifier)
                          .removeTrackFromQueues(t.id);
                      if (!mounted) return;
                      setState(() {
                        group.removeWhere((track) => track.id == t.id);
                        if (group.length < 2) groups.remove(group);
                      });
                    },
                  ),
                ),
            ],
          );
        }
        final group = copies[index - 4 - groups.length];
        return ExpansionTile(
          title: Text('${group.length} identical files'),
          children: [
            for (final path in group)
              ListTile(
                title: Text(path),
                subtitle: const Text('File kept on disk'),
              ),
          ],
        );
      },
    ),
  );
}
