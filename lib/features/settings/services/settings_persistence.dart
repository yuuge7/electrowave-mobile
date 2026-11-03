import 'dart:convert';
import 'dart:io';

import '../../../core/services/local_log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AppThemeMode { system, light, dark }

/// ReplayGain mode, applied by mpv itself (it reads the gain tags).
enum ReplayGainMode { off, track, album }

/// Fixed EQ band centre frequencies, in Hz.
const List<int> kEqBandFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

const double kEqMaxGainDb = 12;

/// Selectable "stop after this long without the user touching anything"
/// values, in minutes. 0 disables the check.
const List<int> kInactivityStopChoicesMinutes = [0, 30, 60, 120, 240, 480];

/// User settings that aren't part of the library database.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.dark,
    this.dynamicColor = false,
    this.playbackRate = 1.0,
    this.eqEnabled = false,
    this.eqGainsDb = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.replayGain = ReplayGainMode.off,
    this.skipSilence = false,
    this.fadeOnPause = true,
    this.inactivityStopMinutes = 120,
    this.mono = false,
    this.crossfeed = false,
    this.gapless = false,
    this.eqProfile = 'speaker',
    this.eqProfiles = const {},
    this.eqPresets = const {},
    this.backupFolder,
  });

  final bool mono, crossfeed, gapless;
  final String eqProfile;
  final Map<String, List<double>> eqProfiles, eqPresets;
  final String? backupFolder;
  final AppThemeMode themeMode;

  /// Material You: derive the palette from the system wallpaper.
  final bool dynamicColor;
  final double playbackRate;
  final bool eqEnabled;

  /// Gain per band in dB, parallel to [kEqBandFrequencies].
  final List<double> eqGainsDb;
  final ReplayGainMode replayGain;

  /// Cut silent stretches out of the audio as it plays (mpv `silenceremove`).
  /// Tracks then finish earlier than their tagged duration.
  final bool skipSilence;

  /// Ramp the volume down before pausing and back up on resume, instead of
  /// cutting the waveform mid-cycle.
  final bool fadeOnPause;

  /// Stop playback after this many minutes without any user interaction —
  /// a tap in the app, a notification/widget/headset control, or a media
  /// button. 0 turns the check off. Unlike the sleep timer this keeps
  /// re-arming, so it only fires when the listener really has walked away.
  final int inactivityStopMinutes;

  /// Null when disabled.
  Duration? get inactivityStopTimeout => inactivityStopMinutes > 0
      ? Duration(minutes: inactivityStopMinutes)
      : null;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    bool? dynamicColor,
    double? playbackRate,
    bool? eqEnabled,
    List<double>? eqGainsDb,
    ReplayGainMode? replayGain,
    bool? skipSilence,
    bool? fadeOnPause,
    int? inactivityStopMinutes,
    bool? mono,
    bool? crossfeed,
    bool? gapless,
    String? eqProfile,
    Map<String, List<double>>? eqProfiles,
    Map<String, List<double>>? eqPresets,
    String? backupFolder,
    bool clearBackupFolder = false,
  }) {
    return AppSettings(
      mono: mono ?? this.mono,
      crossfeed: crossfeed ?? this.crossfeed,
      gapless: gapless ?? this.gapless,
      eqProfile: eqProfile ?? this.eqProfile,
      eqProfiles: eqProfiles ?? this.eqProfiles,
      eqPresets: eqPresets ?? this.eqPresets,
      backupFolder: clearBackupFolder
          ? null
          : (backupFolder ?? this.backupFolder),
      themeMode: themeMode ?? this.themeMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      playbackRate: playbackRate ?? this.playbackRate,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqGainsDb: eqGainsDb ?? this.eqGainsDb,
      replayGain: replayGain ?? this.replayGain,
      skipSilence: skipSilence ?? this.skipSilence,
      fadeOnPause: fadeOnPause ?? this.fadeOnPause,
      inactivityStopMinutes:
          inactivityStopMinutes ?? this.inactivityStopMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
    'mono': mono,
    'crossfeed': crossfeed,
    'gapless': gapless,
    'eqProfile': eqProfile,
    'eqProfiles': eqProfiles,
    'eqPresets': eqPresets,
    'backupFolder': backupFolder,
    'themeMode': themeMode.name,
    'dynamicColor': dynamicColor,
    'playbackRate': playbackRate,
    'eqEnabled': eqEnabled,
    'eqGainsDb': eqGainsDb,
    'replayGain': replayGain.name,
    'skipSilence': skipSilence,
    'fadeOnPause': fadeOnPause,
    'inactivityStopMinutes': inactivityStopMinutes,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    List<double> gains() {
      final raw = json['eqGainsDb'];
      if (raw is! List) return List.filled(10, 0);
      final parsed = [
        for (final value in raw)
          (value is num ? value.toDouble() : 0.0).clamp(
            -kEqMaxGainDb,
            kEqMaxGainDb,
          ),
      ];
      // Tolerate a settings file written by a build with a different band
      // count rather than throwing the whole file away.
      if (parsed.length == 5) {
        // Preserve legacy five-band curves by interpolation on the log axis.
        return [
          parsed[0],
          parsed[0],
          (parsed[0] + parsed[1]) / 2,
          parsed[1],
          (parsed[1] + parsed[2]) / 2,
          parsed[2],
          (parsed[2] + parsed[3]) / 2,
          parsed[3],
          (parsed[3] + parsed[4]) / 2,
          parsed[4],
        ];
      }
      if (parsed.length != kEqBandFrequencies.length) {
        return List<double>.filled(kEqBandFrequencies.length, 0);
      }
      return parsed;
    }

    Map<String, List<double>> curves(String key) {
      final raw = json[key];
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.key is String &&
              e.value is List &&
              (e.value as List).length == 10)
            e.key as String: [
              for (final v in e.value)
                (v is num && v.isFinite ? v.toDouble() : 0.0).clamp(-12, 12),
            ],
      };
    }

    return AppSettings(
      mono: json['mono'] == true,
      crossfeed: json['crossfeed'] == true,
      gapless: json['gapless'] == true,
      eqProfile:
          ['speaker', 'headphones', 'bluetooth'].contains(json['eqProfile'])
          ? json['eqProfile'] as String
          : 'speaker',
      eqProfiles: curves('eqProfiles'),
      eqPresets: curves('eqPresets'),
      backupFolder: json['backupFolder'] as String?,
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => AppThemeMode.dark,
      ),
      dynamicColor: json['dynamicColor'] as bool? ?? false,
      playbackRate: ((json['playbackRate'] as num?)?.toDouble() ?? 1.0).clamp(
        0.5,
        2.0,
      ),
      eqEnabled: json['eqEnabled'] as bool? ?? false,
      eqGainsDb: gains(),
      replayGain: ReplayGainMode.values.firstWhere(
        (mode) => mode.name == json['replayGain'],
        orElse: () => ReplayGainMode.off,
      ),
      skipSilence: json['skipSilence'] as bool? ?? false,
      fadeOnPause: json['fadeOnPause'] as bool? ?? true,
      inactivityStopMinutes: switch (json['inactivityStopMinutes']) {
        final num minutes when minutes >= 0 => minutes.toInt(),
        _ => 120,
      },
    );
  }
}

class SettingsPersistence {
  File? _file;
  Future<void> _pending = Future.value();

  Future<File> _settingsFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'settings.json'));
    return _file!;
  }

  Future<AppSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return const AppSettings();
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) {
    _pending = _pending
        .then((_) async {
          final file = await _settingsFile();
          final tmp = File('${file.path}.tmp');
          await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
          await tmp.rename(file.path);
        })
        .catchError((Object e, StackTrace s) {
          LocalLog.record(e, s);
        });
    return _pending;
  }
}
