import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import '../../../core/database/database_provider.dart';
import '../../library/providers/browse_providers.dart';
import '../../library/providers/library_providers.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/deck.dart';
import '../../player/views/sleep_timer_sheet.dart';
import '../providers/settings_providers.dart';
import '../services/notification_diagnostics.dart';
import '../services/settings_persistence.dart';
import '../services/automatic_backups.dart';
import '../services/platform_bootstrap.dart';
import '../services/backup_service.dart';
import '../../../core/services/local_log.dart';
import '../../player/providers/player_providers.dart';
import '../../library/views/library_tools_screen.dart';
import '../../playlists/services/playlist_file_service.dart';
import '../../stats/views/listening_extras_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.page});
  final String? page;
  List<Widget> _pageWidgets(List<Widget> widgets) {
    var section = '';
    final result = <Widget>[];
    for (final widget in widgets) {
      if (widget is _SectionHeader) section = widget.text;
      if ((section == 'Data' ? 'Backup' : section) == page &&
          widget is! Divider) {
        result.add(widget);
      }
    }
    return result;
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final folders = ref.watch(libraryFoldersProvider);
    final summary = page == 'Library'
        ? ref.watch(librarySummaryProvider).value
        : null;
    final missing = ref.watch(missingFilesProvider).value ?? const {};
    final settings = ref.watch(settingsControllerProvider);
    final deletedCount =
        (ref.watch(deletedTracksProvider).value ?? const []).length;

    if (page == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            for (final entry in const {
              'Library': Icons.library_music_outlined,
              'Playback': Icons.play_circle_outline,
              'Audio': Icons.graphic_eq,
              'Appearance': Icons.palette_outlined,
              'Backup': Icons.backup_outlined,
              'About': Icons.info_outline,
            }.entries)
              ListTile(
                leading: Icon(entry.value),
                title: Text(entry.key),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(page: entry.key),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(page!)),
      body: ListView(
        children: _pageWidgets([
          const _SectionHeader('Library'),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Library summary'),
            subtitle: Text(
              summary == null
                  ? 'Reading library…'
                  : '${summary['songs']} songs · ${((summary['ms'] as int) / 3600000).toStringAsFixed(1)} hours · ${((summary['bytes'] as int) / 1048576).toStringAsFixed(1)} MB\n${(summary['formats'] as Map).entries.map((e) => '${e.key}: ${e.value}').join(' · ')}',
            ),
          ),
          for (final folder in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Forget folder',
                icon: const Icon(Icons.close),
                onPressed: () => ref
                    .read(scanControllerProvider.notifier)
                    .forgetFolder(folder),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Add library folder'),
            onTap: scan.running
                ? null
                : () async {
                    final ok = await ref
                        .read(scanControllerProvider.notifier)
                        .pickAndScanFolder();
                    if (!ok && context.mounted) context.push('/permission');
                  },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Duplicate finder'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LibraryToolsScreen(duplicates: true),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Re-scan library'),
            subtitle: Text('${folders.length} saved folders'),
            enabled: !scan.running,
            onTap: () async {
              if (folders.isNotEmpty) {
                await ref.read(scanControllerProvider.notifier).rescanAll();
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
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text('${missing.length} tracks point to missing files'),
              subtitle: const Text(
                'They are flagged in the library and skipped during playback',
              ),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Removed tracks'),
            subtitle: Text(
              deletedCount == 0
                  ? 'Nothing removed'
                  : '$deletedCount track${deletedCount == 1 ? '' : 's'} can be restored',
            ),
            onTap: () => context.push('/trash'),
          ),
          const Divider(),
          const _SectionHeader('Playback'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Private session'),
            subtitle: const Text(
              'Pause recording plays, skips and listening time',
            ),
            value: ref.watch(privateSessionProvider),
            onChanged: ref
                .read(playerControllerProvider.notifier)
                .setPrivateSession,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.multitrack_audio),
            title: const Text('Gapless playback'),
            subtitle: const Text(
              'Preload only the next track. Turn off if your device has transition issues.',
            ),
            value: settings.gapless,
            onChanged: ref.read(settingsControllerProvider.notifier).setGapless,
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep timer'),
            subtitle: const Text('Close the app after a delay'),
            onTap: () => showSleepTimerSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: const Text('Stop when unattended'),
            subtitle: Text(
              settings.inactivityStopMinutes == 0
                  ? 'Off · keep playing until stopped'
                  : 'After ${formatInactivityStop(settings.inactivityStopMinutes)} without touching anything',
            ),
            onTap: () => showAppSheet<void>(
              context,
              builder: (sheetContext) => const _InactivityStopSheet(),
            ),
          ),
          const _NotificationPermissionTile(),
          const _BatteryExemptionTile(),
          const _SectionHeader('Audio'),
          SwitchListTile(
            secondary: const Icon(Icons.hearing),
            title: const Text('Mono audio'),
            subtitle: const Text('Hear both channels in either ear'),
            value: settings.mono,
            onChanged: ref.read(settingsControllerProvider.notifier).setMono,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.headphones),
            title: const Text('Headphone crossfeed'),
            subtitle: const Text(
              'Blend a little of each stereo channel into the other',
            ),
            value: settings.crossfeed,
            onChanged: ref
                .read(settingsControllerProvider.notifier)
                .setCrossfeed,
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('Calculate missing ReplayGain'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LibraryToolsScreen(duplicates: false),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Equalizer'),
            subtitle: Text(
              settings.eqEnabled
                  ? 'On · ${settings.replayGain == ReplayGainMode.off ? 'no normalization' : 'normalizing'}'
                  : 'Off',
            ),
            onTap: () => context.push('/equalizer'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.content_cut),
            title: const Text('Skip silence'),
            subtitle: const Text(
              'Cut silent stretches out — tracks end before their tagged length',
            ),
            value: settings.skipSilence,
            onChanged: ref
                .read(settingsControllerProvider.notifier)
                .setSkipSilence,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on),
            title: const Text('Fade on pause'),
            subtitle: const Text(
              'Ramp the volume instead of cutting the audio',
            ),
            value: settings.fadeOnPause,
            onChanged: ref
                .read(settingsControllerProvider.notifier)
                .setFadeOnPause,
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Playback speed'),
            subtitle: Text(
              settings.playbackRate == 1.0
                  ? 'Normal'
                  : '${settings.playbackRate}×',
            ),
            onTap: () => showAppSheet<void>(
              context,
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
            onTap: () => showAppSheet<void>(
              context,
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
            subtitle: const Text('Track info and controls without unlocking'),
            onTap: () async {
              final supported =
                  await HomeWidget.isRequestPinWidgetSupported() ?? false;
              if (!context.mounted) return;
              if (!supported) {
                _toast(
                  context,
                  'Your launcher doesn’t support adding widgets from apps — '
                  'long-press the home screen instead',
                );
                return;
              }
              final provider = await showDialog<String>(
                context: context,
                builder: (c) => SimpleDialog(
                  title: const Text('Widget size'),
                  children: [
                    for (final entry in const {
                      'ElectrowaveWidgetProvider': 'Compact · 3×1',
                      'ElectrowaveArtWidgetProvider': 'Cover art · 2×2',
                      'ElectrowaveWideWidgetProvider':
                          'Progress and favourite · 4×2',
                    }.entries)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(c, entry.key),
                        child: Text(entry.value),
                      ),
                  ],
                ),
              );
              if (provider != null) {
                await HomeWidget.requestPinWidget(
                  qualifiedAndroidName:
                      'com.example.electrowave_mobile.$provider',
                );
              }
            },
          ),
          const Divider(),
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Weekly automatic backups'),
            subtitle: Text(
              settings.backupFolder == null
                  ? 'Off · choose a folder to keep the latest 5'
                  : 'On · every week, latest 5 kept',
            ),
            onTap: () async {
              try {
                final uri = await AutomaticBackups.chooseFolder();
                if (uri == null) return;
                await ref
                    .read(settingsControllerProvider.notifier)
                    .setBackupFolder(uri);
                await AutomaticBackups.configure(uri);
                await ref.read(playerControllerProvider.notifier).flushState();
                await AutomaticBackups.run(
                  ref.read(backupServiceProvider),
                  uri,
                  force: true,
                );
                if (context.mounted) {
                  _toast(context, 'Automatic backups enabled');
                }
              } catch (e) {
                if (context.mounted) {
                  _toast(context, 'Could not enable backups: $e');
                }
              }
            },
            trailing: settings.backupFolder == null
                ? null
                : IconButton(
                    tooltip: 'Disable automatic backups',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await AutomaticBackups.configure(null);
                      await ref
                          .read(settingsControllerProvider.notifier)
                          .setBackupFolder(null);
                    },
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('Undo last restore'),
            subtitle: const Text('Stage the safety copy for the next launch'),
            onTap: () async {
              try {
                final dir = await getApplicationDocumentsDirectory();
                await BackupService.stageBytes(
                  await File(
                    '${dir.path}/restore-safety.ewbackup',
                  ).readAsBytes(),
                );
                if (context.mounted) {
                  _toast(context, 'Safety copy staged. Restart to restore.');
                }
              } catch (e) {
                if (context.mounted) {
                  _toast(context, 'No usable safety copy: $e');
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export complete backup'),
            subtitle: const Text(
              'Library, playlists, stats, settings, EQ, queue and artwork',
            ),
            onTap: () async {
              try {
                await ref.read(playerControllerProvider.notifier).flushState();
                final path = await ref
                    .read(backupServiceProvider)
                    .exportDatabase();
                if (!context.mounted) return;
                _toast(
                  context,
                  path == null ? 'Export cancelled' : 'Backup exported',
                );
              } catch (e) {
                if (context.mounted) _toast(context, 'Export failed: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import backup'),
            subtitle: const Text('Applied safely on the next app launch'),
            onTap: () async {
              try {
                final staged = await ref
                    .read(backupServiceProvider)
                    .stageImport();
                if (!context.mounted) return;
                if (staged) {
                  _toast(
                    context,
                    'Backup staged — restart the app to apply it',
                  );
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
            leading: Icon(
              Icons.delete_sweep,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Clear play history'),
            subtitle: const Text('Resets stats and play counts'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Clear play history?'),
                  content: const Text(
                    'All listening stats and play counts will be deleted. '
                    'This cannot be undone.',
                  ),
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
                await ref
                    .read(playerControllerProvider.notifier)
                    .clearPlayHistory();
                if (context.mounted) _toast(context, 'Play history cleared');
              }
            },
          ),
          const Divider(),
          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Electrowave'),
            subtitle: Text(
              'Version ${ref.watch(appVersionProvider).value ?? '…'} · MIT licence',
            ),
          ),
          const ListTile(
            title: Text('No internet. No account. No tracking.'),
            subtitle: Text(
              'Nothing leaves your phone. Move data only through files you choose to export.',
            ),
          ),
          ListTile(
            title: const Text('Licences'),
            leading: const Icon(Icons.description_outlined),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Electrowave',
              applicationVersion: ref.read(appVersionProvider).value,
              applicationLegalese:
                  'MIT License · Copyright 2026 Electrowave Mobile contributors',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Export crash log'),
            subtitle: const Text(
              'Saved locally; share it by hand if you choose',
            ),
            onTap: () async {
              final bytes = await LocalLog.export();
              await FilePicker.platform.saveFile(
                dialogTitle: 'Export local crash log',
                fileName: 'electrowave-crash.log',
                type: FileType.any,
                bytes: Uint8List.fromList(bytes),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Listening patterns'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ListeningExtrasScreen()),
            ),
          ),
          for (final csv in [true, false])
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text('Export stats as ${csv ? 'CSV' : 'JSON'}'),
              onTap: () async {
                try {
                  await ref
                      .read(playerControllerProvider.notifier)
                      .flushState();
                  await StatsExport.save(ref.read(databaseProvider), csv: csv);
                } catch (e) {
                  if (context.mounted) _toast(context, 'Export failed: $e');
                }
              },
            ),
        ]),
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

    return RadioGroup<AppThemeMode>(
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
    );
  }
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  static const List<double> _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(
      settingsControllerProvider.select((settings) => settings.playbackRate),
    );
    final controller = ref.read(settingsControllerProvider.notifier);

    return RadioGroup<double>(
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
    final minutes = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.inactivityStopMinutes,
      ),
    );
    final controller = ref.read(settingsControllerProvider.notifier);

    return RadioGroup<int>(
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
              'notification, the widget or a headset button for this '
              'long. Skipping tracks on its own does not count.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final value in kInactivityStopChoicesMinutes)
            RadioListTile<int>(
              value: value,
              title: Text(value == 0 ? 'Off' : formatInactivityStop(value)),
            ),
          const SizedBox(height: 8),
        ],
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
    extends ConsumerState<_NotificationPermissionTile>
    with WidgetsBindingObserver {
  final NotificationDiagnostics _diagnostics = NotificationDiagnostics();
  NotificationBlock? _block;

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
    // Picks up a change made on the system settings page we sent them to.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final block = await _diagnostics.check();
    if (mounted) setState(() => _block = block);
  }

  Future<void> _fix() async {
    // Only the app-level block can still be resolved by the runtime dialog,
    // and only while it hasn't been permanently denied. Everything else has
    // to be switched back on by hand.
    if (_block == NotificationBlock.app) {
      if (await ref.read(permissionServiceProvider).requestNotifications()) {
        await _refresh();
        return;
      }
    }
    await _diagnostics.openSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final block = _block;
    final ok = block == NotificationBlock.none;

    return ListTile(
      leading: Icon(
        ok
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        color: ok || block == null ? null : Theme.of(context).colorScheme.error,
      ),
      title: const Text('Playback notification'),
      subtitle: Text(switch (block) {
        null => 'Checking…',
        NotificationBlock.none =>
          'Notification and lock screen controls are allowed',
        NotificationBlock.app =>
          'Notifications are off for Electrowave. Tap to allow',
        NotificationBlock.channel =>
          'The "Playback" notification category is switched off — that hides '
              'the player controls even though the permission is granted. '
              'Tap to turn it back on',
        NotificationBlock.notCreatedYet =>
          'Play something once to create the notification',
      }),
      trailing: ok
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: ok || block == NotificationBlock.notCreatedYet ? null : _fix,
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
    final exempt = await ref
        .read(permissionServiceProvider)
        .hasBatteryExemption();
    if (mounted) setState(() => _exempt = exempt);
  }

  @override
  Widget build(BuildContext context) {
    final exempt = _exempt;
    return ListTile(
      leading: const Icon(Icons.battery_charging_full),
      title: const Text('Unrestricted background playback'),
      subtitle: Text(
        exempt == true
            ? 'Battery optimization is off for Electrowave'
            : 'Stop the system from killing playback in the background',
      ),
      trailing: exempt == true
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
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

/// Region names are engraved panel labels. They used to be accent-coloured,
/// which spent the signal colour on a heading — the accent means "this is
/// live", and a section title is never that.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SectionHeader(text);
}
