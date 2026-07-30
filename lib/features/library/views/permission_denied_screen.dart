import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/library_providers.dart';
import '../services/permission_service.dart';

/// Friendly explainer shown when audio/storage permission is denied.
class PermissionDeniedScreen extends ConsumerWidget {
  const PermissionDeniedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permission needed')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.music_off,
                size: 72,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 24),
            Text(
              'Electrowave needs access to your music',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'To scan and play your audio files, the app needs the '
              '"Music & audio" permission (or storage access on older '
              'Android versions).\n\n'
              'Your files never leave the device — there is no internet '
              'upload, no telemetry, no account.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () async {
                final result = await ref
                    .read(permissionServiceProvider)
                    .requestAudioAccess();
                if (!context.mounted) return;
                if (result == AudioPermissionResult.granted) {
                  context.pop();
                } else if (result ==
                    AudioPermissionResult.permanentlyDenied) {
                  await ref.read(permissionServiceProvider).openSettings();
                }
              },
              child: const Text('Grant permission'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(permissionServiceProvider).openSettings(),
              child: const Text('Open app settings'),
            ),
          ],
        ),
      ),
    );
  }
}
