import 'package:electrowave_mobile/features/player/services/listening_meter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two stats that were wrong — "time listened" and the play count — both
/// come off this meter, so the cases below are the ones that used to be
/// miscounted.
void main() {
  final start = DateTime(2026, 8, 7, 12);

  ListeningMeter seeded({
    Duration position = Duration.zero,
    DateTime? at,
    double rate = 1.0,
  }) {
    final meter = ListeningMeter()
      ..add(position: position, at: at ?? start, playing: true, rate: rate);
    return meter;
  }

  group('ListeningMeter', () {
    test('counts steady playback', () {
      final meter = seeded();
      for (var tick = 1; tick <= 5; tick++) {
        meter.add(
          position: Duration(milliseconds: 200 * tick),
          at: start.add(Duration(milliseconds: 200 * tick)),
          playing: true,
          rate: 1,
        );
      }
      expect(meter.listenedMs, 1000);
    });

    test('counts a long gap between ticks in full', () {
      // Ticks bunch up while the screen is off; the audio still played.
      final meter = seeded();
      meter.add(
        position: const Duration(minutes: 1),
        at: start.add(const Duration(minutes: 1)),
        playing: true,
        rate: 1,
      );
      expect(meter.listenedMs, 60000);
    });

    test('a track played at 2x costs half the listening time', () {
      final meter = seeded(rate: 2);
      meter.add(
        position: const Duration(seconds: 20),
        at: start.add(const Duration(seconds: 10)),
        playing: true,
        rate: 2,
      );
      expect(meter.listenedMs, 10000);
      // ...but the whole twenty seconds of the recording went past.
      expect(meter.heardMs, 20000);
    });

    test('a track played at 0.75x costs more listening time than it runs', () {
      final meter = seeded(rate: 0.75);
      meter.add(
        position: const Duration(seconds: 60),
        at: start.add(const Duration(seconds: 80)),
        playing: true,
        rate: 0.75,
      );
      expect(meter.listenedMs, 80000);
      expect(meter.heardMs, 60000);
    });

    test('caps a forward scrub at what the wall clock allows', () {
      final meter = seeded();
      meter.add(
        position: const Duration(minutes: 2),
        at: start.add(const Duration(milliseconds: 200)),
        playing: true,
        rate: 1,
      );
      // The 200 ms that really elapsed, not the two minutes jumped over.
      expect(meter.listenedMs, 200);
      expect(meter.heardMs, 200);
    });

    test('ignores a seek backwards', () {
      final meter = seeded(position: const Duration(seconds: 30));
      meter.add(
        position: Duration.zero,
        at: start.add(const Duration(milliseconds: 200)),
        playing: true,
        rate: 1,
      );
      expect(meter.listenedMs, 0);
    });

    test('ignores ticks delivered while paused', () {
      final meter = seeded();
      meter.add(
        position: const Duration(seconds: 5),
        at: start.add(const Duration(seconds: 5)),
        playing: false,
        rate: 1,
      );
      expect(meter.listenedMs, 0);
    });

    test('does not count the gap a pause spans', () {
      final meter = seeded();
      // Paused at 5 s, resumed a minute later.
      meter.add(
        position: const Duration(seconds: 5),
        at: start.add(const Duration(seconds: 5)),
        playing: false,
        rate: 1,
      );
      meter.add(
        position: const Duration(seconds: 6),
        at: start.add(const Duration(seconds: 65)),
        playing: true,
        rate: 1,
      );
      expect(meter.listenedMs, 1000);
    });

    test('reset starts a fresh count', () {
      final meter = seeded();
      meter.add(
        position: const Duration(seconds: 10),
        at: start.add(const Duration(seconds: 10)),
        playing: true,
        rate: 1,
      );
      meter.reset();
      expect(meter.listenedMs, 0);

      // The first tick after a reset only seeds the baseline.
      meter.add(
        position: const Duration(seconds: 30),
        at: start.add(const Duration(seconds: 30)),
        playing: true,
        rate: 1,
      );
      expect(meter.listenedMs, 0);
    });
  });

  group('scrobbleThresholdMs', () {
    test('is a quarter of a normal track', () {
      expect(scrobbleThresholdMs(const Duration(minutes: 4)), 60000);
    });

    test('is capped for long mixes', () {
      expect(
        scrobbleThresholdMs(const Duration(hours: 1)),
        scrobbleCap.inMilliseconds,
      );
    });

    test('a scrub cannot reach it, listening can', () {
      const duration = Duration(minutes: 4);
      final meter = ListeningMeter()
        ..add(position: Duration.zero, at: start, playing: true, rate: 1);

      // Scrub straight past the 25% mark.
      meter.add(
        position: const Duration(minutes: 2),
        at: start.add(const Duration(milliseconds: 200)),
        playing: true,
        rate: 1,
      );
      expect(meter.heardMs, lessThan(scrobbleThresholdMs(duration)));

      // Then actually listen for a minute.
      meter.add(
        position: const Duration(minutes: 3),
        at: start.add(const Duration(seconds: 60, milliseconds: 200)),
        playing: true,
        rate: 1,
      );
      expect(meter.heardMs, greaterThanOrEqualTo(scrobbleThresholdMs(duration)));
    });

    test('a track played fast still counts as played', () {
      const duration = Duration(minutes: 4);
      final meter = ListeningMeter()
        ..add(position: Duration.zero, at: start, playing: true, rate: 2);

      // A minute of the recording, heard in thirty seconds at 2×.
      meter.add(
        position: const Duration(minutes: 1),
        at: start.add(const Duration(seconds: 30)),
        playing: true,
        rate: 2,
      );
      expect(meter.listenedMs, 30000);
      expect(meter.heardMs, greaterThanOrEqualTo(scrobbleThresholdMs(duration)));
    });
  });
}
