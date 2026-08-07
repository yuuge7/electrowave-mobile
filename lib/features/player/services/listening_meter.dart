import 'dart:math';

/// Measures listening from the player's position ticks.
///
/// Kept apart from the player controller because both stats that used to be
/// wrong are decided here — "time listened" and, through
/// [scrobbleThresholdMs], the play count — and this way they can be tested
/// without a player.
///
/// Two figures come out of it, and they are not the same thing once the
/// playback speed leaves 1×:
///
/// * [listenedMs] is time actually spent listening. A one-minute track at
///   0.75× is eighty seconds of it; at 1.5× it is forty. This is what the
///   stats store.
/// * [heardMs] is how much of the recording went past, in its own timeline.
///   That is what a play threshold has to be measured against — a track is
///   played through whatever speed it ran at.
///
/// The rules:
///
/// * Only ticks delivered while playing count.
/// * A step counts for the smaller of the time it claims and the time that
///   really elapsed. That is what tells playback apart from a seek, without
///   assuming anything about how often ticks arrive — ticks bunch up badly
///   while the screen is off, and a fixed window threw that real playback
///   away.
class ListeningMeter {
  Duration? _lastPosition;
  DateTime? _lastAt;

  /// Wall-clock time spent listening since the last [reset], in milliseconds.
  int listenedMs = 0;

  /// Recording heard since the last [reset], in milliseconds of its own
  /// timeline.
  int heardMs = 0;

  /// Feeds one position tick and returns the listening milliseconds it added.
  int add({
    required Duration position,
    required DateTime at,
    required bool playing,
    required double rate,
  }) {
    final lastPosition = _lastPosition;
    final lastAt = _lastAt;
    _lastPosition = position;
    _lastAt = at;

    if (lastPosition == null || lastAt == null) return 0;
    if (!playing) return 0;

    final step = position - lastPosition;
    if (step <= Duration.zero) return 0;

    final elapsed = at.difference(lastAt);
    if (elapsed < Duration.zero) return 0;

    // How long this much of the recording takes to play at this speed. A
    // forward scrub claims far more than the clock allows, so the elapsed
    // time wins and the jump is not counted as listening.
    final safeRate = rate > 0 ? rate : 1.0;
    final claimed = (step.inMilliseconds / safeRate).round();
    final counted = min(claimed, elapsed.inMilliseconds);

    listenedMs += counted;
    heardMs += (counted * safeRate).round();
    return counted;
  }

  /// Starts counting again — a new track, or the same track re-loaded.
  void reset() {
    listenedMs = 0;
    heardMs = 0;
    _lastPosition = null;
    _lastAt = null;
  }
}

/// Upper bound on the audio needed to book the first play, so an hour-long mix
/// does not need fifteen minutes before it counts as played.
const scrobbleCap = Duration(minutes: 4);

/// How much of a track of [duration] must go past before a play is booked —
/// measured against [ListeningMeter.heardMs], so the speed it ran at makes no
/// difference to whether it counts as played.
///
/// Measured playback rather than where the position marker sits: scrubbing
/// past the mark, or mpv re-emitting a position after the filter chain is
/// rebuilt (a speed or EQ change does that), would otherwise each book a play
/// — which is how a track collects hundreds of plays against a few hours of
/// listening.
int scrobbleThresholdMs(Duration duration) =>
    min((duration.inMilliseconds * 0.25).round(), scrobbleCap.inMilliseconds);
