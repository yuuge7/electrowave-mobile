import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../library/providers/library_providers.dart';
import '../../player/providers/player_providers.dart';
import '../services/backup_service.dart';
import '../services/settings_persistence.dart';

final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));

final settingsPersistenceProvider =
    Provider<SettingsPersistence>((ref) => SettingsPersistence());

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Loads persisted settings on first build and pushes audio-affecting ones
/// (speed, EQ, ReplayGain) into the player whenever they change.
class SettingsController extends Notifier<AppSettings> {
  SettingsPersistence get _persistence => ref.read(settingsPersistenceProvider);

  @override
  AppSettings build() {
    Future.microtask(_restore);
    return const AppSettings();
  }

  Future<void> _restore() async {
    final saved = await _persistence.load();
    state = saved;
    await _applyToPlayer(saved);
  }

  Future<void> _applyToPlayer(AppSettings settings) async {
    final handler = ref.read(audioHandlerProvider);
    await handler.setRate(settings.playbackRate);
    await handler.applyAudioSettings(settings);
    handler.setInactivityTimeout(settings.inactivityStopTimeout);
  }

  Future<void> _update(AppSettings next, {bool audio = false}) async {
    state = next;
    unawaited(_persistence.save(next));
    if (audio) await _applyToPlayer(next);
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      _update(state.copyWith(themeMode: mode));

  Future<void> setDynamicColor(bool enabled) =>
      _update(state.copyWith(dynamicColor: enabled));

  Future<void> setPlaybackRate(double rate) =>
      _update(state.copyWith(playbackRate: rate.clamp(0.5, 2.0)), audio: true);

  Future<void> setEqEnabled(bool enabled) =>
      _update(state.copyWith(eqEnabled: enabled), audio: true);

  Future<void> setEqBand(int index, double gainDb) {
    if (index < 0 || index >= kEqBandFrequencies.length) {
      return Future.value();
    }
    final gains = List<double>.from(state.eqGainsDb);
    while (gains.length < kEqBandFrequencies.length) {
      gains.add(0);
    }
    gains[index] = gainDb.clamp(-kEqMaxGainDb, kEqMaxGainDb);
    return _update(state.copyWith(eqGainsDb: gains), audio: true);
  }

  Future<void> resetEq() => _update(
        state.copyWith(
          eqGainsDb: List<double>.filled(kEqBandFrequencies.length, 0),
        ),
        audio: true,
      );

  Future<void> setReplayGain(ReplayGainMode mode) =>
      _update(state.copyWith(replayGain: mode), audio: true);

  Future<void> setSkipSilence(bool enabled) =>
      _update(state.copyWith(skipSilence: enabled), audio: true);

  Future<void> setFadeOnPause(bool enabled) =>
      _update(state.copyWith(fadeOnPause: enabled), audio: true);

  /// 0 disables the no-interaction auto-stop.
  Future<void> setInactivityStopMinutes(int minutes) => _update(
        state.copyWith(inactivityStopMinutes: minutes < 0 ? 0 : minutes),
        audio: true,
      );
}

/// IDs of library tracks whose files no longer exist on disk (e.g. after a
/// backup import onto a device with different files). Flagged in the UI and
/// skipped by playback instead of crashing it.
final missingFilesProvider = FutureProvider<Set<int>>((ref) async {
  final tracks = await ref.watch(libraryTracksProvider.future);
  final missing = <int>{};
  for (final track in tracks) {
    if (!await File(track.filePath).exists()) {
      missing.add(track.id);
    }
  }
  return missing;
});
