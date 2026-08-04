import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import '../../../core/database/database_provider.dart';
import '../../library/providers/browse_providers.dart';
import '../../library/providers/library_providers.dart';
import '../../player/views/sleep_timer_sheet.dart';
import '../providers/settings_providers.dart';
import '../services/settings_persistence.dart';

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
    final settings = ref.watch(settingsControllerProvider);
    final deletedCount =
        (ref.watch(deletedTracksProvider).value ?? const []).length;

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
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Removed tracks'),
            subtitle: Text(deletedCount == 0
                ? 'Nothing removed'
                : '$deletedCount track${deletedCount == 1 ? '' : 's'} can be restored'),
            onTap: () => context.push('/trash'),
          ),
          const Divider(),
          const _SectionHeader('Playback'),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep timer'),
            subtitle: const Text('Pause playback after a delay'),
            onTap: () => showSleepTimerSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: const Text('Stop when unattended'),
            subtitle: Text(settings.inactivityStopMinutes == 0
                ? 'Off · keep playing until stopped'
                : 'After ${formatInactivityStop(settings.inactivityStopMinutes)} without touching anything'),
            onTap: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => const _InactivityStopSheet(),
            ),
          ),
          const _NotificationPermissionTile(),
          const _BatteryExemptionTile(),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Equalizer'),
            subtitle: Text(settings.eqEnabled
                ? 'On · ${settings.replayGain == ReplayGainMode.off ? 'no normalization' : 'normalizing'}'
                : 'Off'),
            onTap: () => context.push('/equalizer'),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Playback speed'),
            subtitle: Text(settings.playbackRate == 1.0
                ? 'Normal'
                : '${settings.playbackRate}×'),
            onTap: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => const _SpeedSheet(),
            ),
          ),
          const Divider(),
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(switch (settings.themeMode) {
              AppThemeMode.system => 'Follow system',
              AppThemeMode.light => 'Light',
              AppThemeMode.dark => 'Dark',
            }),
            onTap: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => const _ThemeSheet(),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.palette_outlined),
            title: const Text('Material You colors'),
            subtitle: const Text('Match the system wallpaper palette'),
            value: settings.dynamicColor,
            onChanged: ref
                .read(settingsControllerProvider.notifier)
                .setDynamicColor,
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('Add home screen widget'),
            subtitle:
                const Text('Track info and controls without unlocking'),
            onTap: () async {
              final supported =
                  await HomeWidget.isRequestPinWidgetSupported() ?? false;
              if (!context.mounted) return;
              if (!supported) {
                _toast(
                    context,
                    'Your launcher doesn’t support adding widgets from apps — '
                    'long-press the home screen instead');
                return;
              }
              await HomeWidget.requestPinWidget(
                  androidName: 'ElectrowaveWidgetProvider');
            },
          ),
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

class _ThemeSheet extends ConsumerWidget {
  const _ThemeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return SafeArea(
      child: RadioGroup<AppThemeMode>(
        groupValue: settings.themeMode,
        onChanged: (mode) {
          if (mode != null) controller.setThemeMode(mode);
        },
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AppThemeMode>(
              value: AppThemeMode.system,
              title: Text('Follow system'),
            ),
            RadioListTile<AppThemeMode>(
              value: AppThemeMode.light,
              title: Text('Light'),
            ),
            RadioListTile<AppThemeMode>(
              value: AppThemeMode.dark,
              title: Text('Dark'),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(
        settingsControllerProvider.select((settings) => settings.playbackRate));
    final controller = ref.read(settingsControllerProvider.notifier);

    return SafeArea(
      child: RadioGroup<double>(
        groupValue: rate,
        onChanged: (value) {
          if (value != null) controller.setPlaybackRate(value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in _rates)
              RadioListTile<double>(
                value: value,
                title: Text(value == 1.0 ? 'Normal (1×)' : '$value×'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// "30 minutes" / "2 hours" for a whole number of minutes.
String formatInactivityStop(int minutes) {
  if (minutes % 60 != 0) return '$minutes minutes';
  final hours = minutes ~/ 60;
  return hours == 1 ? '1 hour' : '$hours hours';
}

class _InactivityStopSheet extends ConsumerWidget {
  const _InactivityStopSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(settingsControllerProvider
        .select((settings) => settings.inactivityStopMinutes));
    final controller = ref.read(settingsControllerProvider.notifier);

    return SafeArea(
      child: RadioGroup<int>(
        groupValue: minutes,
        onChanged: (value) {
          if (value != null) controller.setInactivityStopMinutes(value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Playback stops if you have not touched the app, the '
                'notification, the widget or a headset button for this long. '
                'Skipping tracks on its own does not count.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final value in kInactivityStopChoicesMinutes)
              RadioListTile<int>(
                value: value,
                title: Text(
                    value == 0 ? 'Off' : formatInactivityStop(value)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// POST_NOTIFICATIONS status + request. Without it Android 13+ drops the
/// media notification and lock screen controls entirely while audio keeps
/// playing, which reads as "the app is broken" — so surface it.
class _NotificationPermissionTile extends ConsumerStatefulWidget {
  const _NotificationPermissionTile();

  @override
  ConsumerState<_NotificationPermissionTile> createState() =>
      _NotificationPermissionTileState();
}

class _NotificationPermissionTileState
    extends ConsumerState<_NotificationPermissionTile> with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Picks up a grant made on the system settings page we sent them to.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final granted =
        await ref.read(permissionServiceProvider).hasNotificationPermission();
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    return ListTile(
      leading: Icon(
        granted == false
            ? Icons.notifications_off_outlined
            : Icons.notifications_active_outlined,
        color: granted == false ? Theme.of(context).colorScheme.error : null,
      ),
      title: const Text('Playback notification'),
      subtitle: Text(granted == true
          ? 'Notification and lock screen controls are allowed'
          : 'Blocked — playback controls cannot be shown. Tap to allow'),
      trailing: granted == true
          ? Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: granted == true
          ? null
          : () async {
              final service = ref.read(permissionServiceProvider);
              // A permanently denied permission no longer raises the system
              // dialog, so fall through to the app's settings page.
              if (!await service.requestNotifications()) {
                await service.openSettings();
              }
              await _refresh();
            },
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
