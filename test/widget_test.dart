import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave_mobile/features/player/services/playback_persistence.dart';
import 'package:electrowave_mobile/features/settings/services/settings_persistence.dart';

void main() {
  group('PersistedPlayback', () {
    test('round-trips through JSON', () {
      const original = PersistedPlayback(
        currentTrackId: 42,
        positionMs: 123456,
        contextTrackIds: [1, 2, 42, 7],
        contextName: 'Liked songs',
        manualQueueIds: [9, 8],
        contextIndex: 2,
        shuffle: true,
        shuffleOrder: [2, 0, 3, 1],
        repeatIndex: 1,
        fromManualQueue: false,
      );

      final restored = PersistedPlayback.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.currentTrackId, 42);
      expect(restored.positionMs, 123456);
      expect(restored.contextTrackIds, [1, 2, 42, 7]);
      expect(restored.contextName, 'Liked songs');
      expect(restored.manualQueueIds, [9, 8]);
      expect(restored.contextIndex, 2);
      expect(restored.shuffle, isTrue);
      expect(restored.shuffleOrder, [2, 0, 3, 1]);
      expect(restored.repeatIndex, 1);
      expect(restored.fromManualQueue, isFalse);
    });

    test('tolerates missing fields with defaults', () {
      final restored = PersistedPlayback.fromJson({'currentTrackId': 5});

      expect(restored, isNotNull);
      expect(restored!.currentTrackId, 5);
      expect(restored.positionMs, 0);
      expect(restored.contextTrackIds, isEmpty);
      expect(restored.contextIndex, -1);
      expect(restored.shuffle, isFalse);
      expect(restored.repeatIndex, 0);
    });
  });

  group('AppSettings', () {
    test('round-trips through JSON', () {
      const original = AppSettings(
        themeMode: AppThemeMode.light,
        dynamicColor: true,
        playbackRate: 1.5,
        eqEnabled: true,
        eqGainsDb: [6, -3, 0, 4.5, 9],
        replayGain: ReplayGainMode.album,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.themeMode, AppThemeMode.light);
      expect(restored.dynamicColor, isTrue);
      expect(restored.playbackRate, 1.5);
      expect(restored.eqEnabled, isTrue);
      expect(restored.eqGainsDb, [6, -3, 0, 4.5, 9]);
      expect(restored.replayGain, ReplayGainMode.album);
    });

    test('falls back to defaults on unknown enum values', () {
      final restored = AppSettings.fromJson({
        'themeMode': 'sepia',
        'replayGain': 'loudest',
      });

      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.replayGain, ReplayGainMode.off);
    });

    test('clamps out-of-range values from a hand-edited file', () {
      final restored = AppSettings.fromJson({
        'playbackRate': 12.0,
        'eqGainsDb': [99, -99, 0, 0, 0],
      });

      expect(restored.playbackRate, 2.0);
      expect(restored.eqGainsDb[0], kEqMaxGainDb);
      expect(restored.eqGainsDb[1], -kEqMaxGainDb);
    });

    test('resets EQ gains written with a different band count', () {
      final restored = AppSettings.fromJson({'eqGainsDb': [1, 2, 3]});

      expect(restored.eqGainsDb.length, kEqBandFrequencies.length);
      expect(restored.eqGainsDb, everyElement(0.0));
    });
  });
}
