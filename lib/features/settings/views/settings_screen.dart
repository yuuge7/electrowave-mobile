import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database_provider.dart';
import '../../library/providers/library_providers.dart';
import '../../player/views/sleep_timer_sheet.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final lastFolder = ref.watch(lastScannedFolderProvider);
    final missing = ref.watch(missingFilesProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Library'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Re-scan library'),
            subtitle: Text(lastFolder ?? 'Scans the last used folder'),
            enabled: !scan.running,
            onTap: () async {
              if (lastFolder != null) {
                await ref
                    .read(scanControllerProvider.notifier)
                    .scanFolder(lastFolder);
              } else {
                final ok = await ref
                    .read(scanControllerProvider.notifier)
                    .pickAndScanFolder();
                if (!ok && context.mounted) context.push('/permission');
              }
            },
          ),
          if (missing.isNotEmpty)
            ListTile(
              leading: Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('${missing.length} tracks point to missing files'),
              subtitle: const Text(
                  'They are flagged in the library and skipped during playback'),
            ),
          const Divider(),
          const _SectionHeader('Playback'),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep timer'),
            subtitle: const Text('Pause playback after a delay'),
            onTap: () => showSleepTimerSheet(context),
          ),
          const _BatteryExemptionTile(),
          const Divider(),
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export database'),
            subtitle: const Text(
                'Save library, playlists and play history to a file'),
            onTap: () async {
              try {
                final path = await ref
                    .read(backupServiceProvider)
                    .exportDatabase();
                if (!context.mounted) return;
                _toast(
                    context,
                    path == null
                        ? 'Export cancelled'
                        : 'Backup exported');
              } catch (e) {
                if (context.mounted) _toast(context, 'Export failed: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import backup'),
            subtitle:
                const Text('Applied safely on the next app launch'),
            onTap: () async {
              try {
                final staged =
                    await ref.read(backupServiceProvider).stageImport();
                if (!context.mounted) return;
                if (staged) {
                  _toast(context,
                      'Backup staged — restart the app to apply it');
                }
              } catch (e) {
                if (context.mounted) {
                  _toast(context, 'Import failed: $e');
                }
              }
            },
          ),
          const Divider(),
          const _SectionHeader('Data'),
          ListTile(
            leading: Icon(Icons.delete_sweep,
                color: Theme.of(context).colorScheme.error),
            title: const Text('Clear play history'),
            subtitle: const Text('Resets stats and play counts'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Clear play history?'),
                  content: const Text(
                      'All listening stats and play counts will be deleted. '
                      'This cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(databaseProvider).clearPlayHistory();
                if (context.mounted) _toast(context, 'Play history cleared');
              }
            },
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Electrowave',
            applicationVersion: '1.0.0',
            aboutBoxChildren: [
              Text('A local music player. Your files, on your phone — '
                  'no streaming, no accounts, no telemetry.'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Battery-optimization exemption status + request. Aggressive OEM power
/// managers kill background playback without it; see PermissionService.
class _BatteryExemptionTile extends ConsumerStatefulWidget {
  const _BatteryExemptionTile();

  @override
  ConsumerState<_BatteryExemptionTile> createState() =>
      _BatteryExemptionTileState();
}

class _BatteryExemptionTileState extends ConsumerState<_BatteryExemptionTile> {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final exempt =
        await ref.read(permissionServiceProvider).hasBatteryExemption();
    if (mounted) setState(() => _exempt = exempt);
  }

  @override
  Widget build(BuildContext context) {
    final exempt = _exempt;
    return ListTile(
      leading: const Icon(Icons.battery_charging_full),
      title: const Text('Unrestricted background playback'),
      subtitle: Text(exempt == true
          ? 'Battery optimization is off for Electrowave'
          : 'Stop the system from killing playback in the background'),
      trailing: exempt == true
          ? Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: exempt == true
          ? null
          : () async {
              await ref
                  .read(permissionServiceProvider)
                  .requestBatteryExemption();
              await _refresh();
            },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
