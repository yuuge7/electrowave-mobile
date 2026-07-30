import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave_mobile/features/player/services/playback_persistence.dart';

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
}
