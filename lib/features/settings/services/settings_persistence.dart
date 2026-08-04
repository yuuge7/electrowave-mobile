import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AppThemeMode { system, light, dark }

/// ReplayGain mode, applied by mpv itself (it reads the gain tags).
enum ReplayGainMode { off, track, album }

/// Fixed EQ band centre frequencies, in Hz.
const List<int> kEqBandFrequencies = [60, 230, 910, 3600, 14000];

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
    this.eqGainsDb = const [0, 0, 0, 0, 0],
    this.replayGain = ReplayGainMode.off,
    this.inactivityStopMinutes = 120,
  });

  final AppThemeMode themeMode;

  /// Material You: derive the palette from the system wallpaper.
  final bool dynamicColor;
  final double playbackRate;
  final bool eqEnabled;

  /// Gain per band in dB, parallel to [kEqBandFrequencies].
  final List<double> eqGainsDb;
  final ReplayGainMode replayGain;

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
    int? inactivityStopMinutes,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      playbackRate: playbackRate ?? this.playbackRate,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqGainsDb: eqGainsDb ?? this.eqGainsDb,
      replayGain: replayGain ?? this.replayGain,
      inactivityStopMinutes:
          inactivityStopMinutes ?? this.inactivityStopMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'dynamicColor': dynamicColor,
        'playbackRate': playbackRate,
        'eqEnabled': eqEnabled,
        'eqGainsDb': eqGainsDb,
        'replayGain': replayGain.name,
        'inactivityStopMinutes': inactivityStopMinutes,
      };

  static AppSettings fromJson(Map<String, dynamic> json) {
    List<double> gains() {
      final raw = json['eqGainsDb'];
      if (raw is! List) return const [0, 0, 0, 0, 0];
      final parsed = [
        for (final value in raw)
          (value is num ? value.toDouble() : 0.0)
              .clamp(-kEqMaxGainDb, kEqMaxGainDb),
      ];
      // Tolerate a settings file written by a build with a different band
      // count rather than throwing the whole file away.
      if (parsed.length != kEqBandFrequencies.length) {
        return List<double>.filled(kEqBandFrequencies.length, 0);
      }
      return parsed;
    }

    return AppSettings(
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => AppThemeMode.dark,
      ),
      dynamicColor: json['dynamicColor'] as bool? ?? false,
      playbackRate:
          ((json['playbackRate'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0),
      eqEnabled: json['eqEnabled'] as bool? ?? false,
      eqGainsDb: gains(),
      replayGain: ReplayGainMode.values.firstWhere(
        (mode) => mode.name == json['replayGain'],
        orElse: () => ReplayGainMode.off,
      ),
      inactivityStopMinutes: switch (json['inactivityStopMinutes']) {
        final num minutes when minutes >= 0 => minutes.toInt(),
        _ => 120,
      },
    );
  }
}

class SettingsPersistence {
  File? _file;

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

  Future<void> save(AppSettings settings) async {
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    } catch (_) {
      // Best effort; a settings write must never break playback.
    }
  }
}
