import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_providers.dart';

class SleepTimerState {
  const SleepTimerState({
    required this.endOfTrack,
    this.endAt,
    this.remaining = Duration.zero,
  });

  /// "End of current track" mode: fires when the current track completes.
  final bool endOfTrack;

  /// When the timer fires (duration mode only).
  final DateTime? endAt;

  /// Remaining time (duration mode only), updated every second.
  final Duration remaining;

  SleepTimerState copyWith({DateTime? endAt, Duration? remaining}) {
    return SleepTimerState(
      endOfTrack: endOfTrack,
      endAt: endAt ?? this.endAt,
      remaining: remaining ?? this.remaining,
    );
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState?>(
        SleepTimerNotifier.new);

class SleepTimerNotifier extends Notifier<SleepTimerState?> {
  Timer? _ticker;
  StreamSubscription<Duration>? _positionSub;
  double _baseVolume = 100;
  bool _fading = false;
  bool _fired = false;

  static const _fadeWindow = Duration(seconds: 5);

  @override
  SleepTimerState? build() {
    ref.onDispose(_teardown);
    return null;
  }

  void startDuration(Duration duration) {
    _teardown();
    _fired = false;
    _baseVolume = ref.read(audioHandlerProvider).volume;
    state = SleepTimerState(
      endOfTrack: false,
      endAt: DateTime.now().add(duration),
      remaining: duration,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void startEndOfTrack() {
    _teardown();
    _fired = false;
    _baseVolume = ref.read(audioHandlerProvider).volume;
    state = const SleepTimerState(endOfTrack: true);
    // Fade over the last seconds of the track.
    final handler = ref.read(audioHandlerProvider);
    _positionSub = handler.player.stream.position.listen((position) {
      final duration = handler.player.state.duration;
      if (duration <= Duration.zero) return;
      final left = duration - position;
      if (left <= _fadeWindow) {
        _applyFade(left);
      } else if (_fading) {
        _clearFade();
      }
    });
  }

  void extend15() {
    final s = state;
    if (s == null) return;
    if (s.endOfTrack) {
      // Extending an end-of-track timer turns it into a 15 minute timer.
      startDuration(const Duration(minutes: 15));
      return;
    }
    _clearFade();
    final base = s.endAt!.isAfter(DateTime.now()) ? s.endAt! : DateTime.now();
    final endAt = base.add(const Duration(minutes: 15));
    state = s.copyWith(
      endAt: endAt,
      remaining: endAt.difference(DateTime.now()),
    );
  }

  void cancel() {
    _teardown();
    state = null;
  }

  /// Pause playback and clear the timer (used at expiry, and by the player
  /// controller when an end-of-track timer sees the track complete).
  Future<void> fireNow() async {
    if (_fired) return;
    _fired = true;
    _ticker?.cancel();
    await ref.read(playerControllerProvider.notifier).pauseFromSleepTimer();
    _clearFade();
    _teardown();
    state = null;
  }

  void _tick() {
    final s = state;
    if (s == null || s.endAt == null) return;
    final remaining = s.endAt!.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      unawaited(fireNow());
      return;
    }
    state = s.copyWith(remaining: remaining);
    if (remaining <= _fadeWindow) {
      _applyFade(remaining);
    }
  }

  void _applyFade(Duration left) {
    _fading = true;
    final fraction =
        (left.inMilliseconds / _fadeWindow.inMilliseconds).clamp(0.0, 1.0);
    unawaited(
        ref.read(audioHandlerProvider).setVolume(_baseVolume * fraction));
  }

  void _clearFade() {
    if (!_fading) return;
    _fading = false;
    unawaited(ref.read(audioHandlerProvider).setVolume(_baseVolume));
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _positionSub?.cancel();
    _positionSub = null;
    if (_fading) {
      _fading = false;
      unawaited(ref.read(audioHandlerProvider).setVolume(_baseVolume));
    }
  }
}
