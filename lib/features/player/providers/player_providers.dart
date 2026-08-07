import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../services/audio_handler.dart';
import '../services/listening_meter.dart';
import '../services/playback_persistence.dart';
import '../services/widget_service.dart';
import 'sleep_timer_provider.dart';

/// Overridden in main() with the handler returned by AudioService.init().
final audioHandlerProvider = Provider<ElectrowaveAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);

/// Transient user-facing playback messages (missing files, etc.).
final playerMessageProvider = StateProvider<String?>((ref) => null);

enum RepeatMode { off, all, one }

class PlayerQueueState {
  const PlayerQueueState({
    this.current,
    this.fromManualQueue = false,
    this.context = const [],
    this.contextName = '',
    this.contextIndex = -1,
    this.manualQueue = const [],
    this.shuffle = false,
    this.shuffleOrder = const [],
    this.repeat = RepeatMode.off,
  });

  final Track? current;

  /// True when [current] was pulled from the manual queue; [contextIndex]
  /// still points at the context position to resume from.
  final bool fromManualQueue;

  final List<Track> context;
  final String contextName;
  final int contextIndex;
  final List<Track> manualQueue;
  final bool shuffle;

  /// Permutation of context indices, used when [shuffle] is on.
  final List<int> shuffleOrder;
  final RepeatMode repeat;

  PlayerQueueState copyWith({
    Track? current,
    bool clearCurrent = false,
    bool? fromManualQueue,
    List<Track>? context,
    String? contextName,
    int? contextIndex,
    List<Track>? manualQueue,
    bool? shuffle,
    List<int>? shuffleOrder,
    RepeatMode? repeat,
  }) {
    return PlayerQueueState(
      current: clearCurrent ? null : (current ?? this.current),
      fromManualQueue: fromManualQueue ?? this.fromManualQueue,
      context: context ?? this.context,
      contextName: contextName ?? this.contextName,
      contextIndex: contextIndex ?? this.contextIndex,
      manualQueue: manualQueue ?? this.manualQueue,
      shuffle: shuffle ?? this.shuffle,
      shuffleOrder: shuffleOrder ?? this.shuffleOrder,
      repeat: repeat ?? this.repeat,
    );
  }

  /// Context tracks still to come after the current one, in play order.
  List<Track> get upcomingContext {
    if (context.isEmpty) return const [];
    final order = shuffle && shuffleOrder.length == context.length
        ? shuffleOrder
        : List<int>.generate(context.length, (i) => i);
    final pos = contextIndex < 0 ? -1 : order.indexOf(contextIndex);
    return [for (var i = pos + 1; i < order.length; i++) context[order[i]]];
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerQueueState>(PlayerController.new);

class PlayerController extends Notifier<PlayerQueueState> {
  ElectrowaveAudioHandler get _handler => ref.read(audioHandlerProvider);
  AppDatabase get _db => ref.read(databaseProvider);
  final PlaybackPersistence _persistence = PlaybackPersistence();
  final WidgetService _widgets = WidgetService();
  final Random _random = Random();

  /// Plays already booked for the current load of the current track.
  int _playsBooked = 0;
  StreamSubscription<Duration>? _positionSub;

  // Measured listening time. Derived from how far the position actually
  // advanced rather than from wall-clock time, so pauses cost nothing and the
  // figure means "this much audio was heard" at any playback speed.
  int? _listenSessionId;
  final ListeningMeter _meter = ListeningMeter();
  int _savedListenedMs = 0;

  /// Writes are throttled: losing the tail of a session to a kill costs a few
  /// seconds of precision, and the row is topped up on every track change.
  static const _listenFlushInterval = Duration(seconds: 15);
  DateTime _lastListenFlush = DateTime.now();

  @override
  PlayerQueueState build() {
    _handler.onSkipToNext = () => next();
    _handler.onSkipToPrevious = () => previous();
    _handler.onCompleted = _handleCompletion;

    _positionSub = _handler.player.stream.position.listen(_onPosition);
    ref.onDispose(() => _positionSub?.cancel());
    ref.onDispose(() => unawaited(_flushListening()));

    // Keep the home screen widget in step with play/pause. Track changes push
    // their own update from _loadAndPlay.
    final playingSub = _handler.player.stream.playing.listen((playing) {
      unawaited(_widgets.update(track: state.current, playing: playing));
      // Pausing is the natural point to bank the running total: the app is
      // most likely to be killed while nothing is playing, and the throttled
      // flush would otherwise lose the last stretch.
      if (!playing) unawaited(_flushListening());
    });
    ref.onDispose(playingSub.cancel);

    // Backfill missing durations once the player knows the real length.
    final durationSub = _handler.player.stream.duration.listen((duration) {
      final current = state.current;
      if (current != null &&
          current.durationMs == 0 &&
          duration > Duration.zero) {
        final ms = duration.inMilliseconds;
        unawaited(_db.updateTrackDurationIfMissing(current.id, ms));
        state = state.copyWith(current: current.copyWith(durationMs: ms));
      }
    });
    ref.onDispose(durationSub.cancel);

    Future.microtask(restore);
    return const PlayerQueueState();
  }

  // ---------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------

  /// Play [track], making [contextTracks] the playback context.
  Future<void> playFromList(
    Track track,
    List<Track> contextTracks,
    String contextName,
  ) async {
    final index = contextTracks.indexWhere((t) => t.id == track.id);
    var next = state.copyWith(
      context: List.of(contextTracks),
      contextName: contextName,
      contextIndex: index < 0 ? 0 : index,
      fromManualQueue: false,
    );
    if (next.shuffle) {
      next = next.copyWith(
        shuffleOrder: _makeShuffleOrder(next.context.length, next.contextIndex),
      );
    }
    state = next;
    await _loadAndPlay(track);
  }

  /// Turn shuffle on and start [contextTracks] from a random track.
  Future<void> shufflePlayList(
    List<Track> contextTracks,
    String contextName,
  ) async {
    if (contextTracks.isEmpty) return;
    final start = _random.nextInt(contextTracks.length);
    state = state.copyWith(
      context: List.of(contextTracks),
      contextName: contextName,
      contextIndex: start,
      fromManualQueue: false,
      shuffle: true,
      shuffleOrder: _makeShuffleOrder(contextTracks.length, start),
    );
    await _loadAndPlay(contextTracks[start]);
  }

  Future<void> togglePlayPause() async {
    if (state.current == null) return;
    if (_handler.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
    unawaited(_saveState());
  }

  Future<void> seek(Duration position) => _handler.seek(position);

  /// Advance. [auto] is true when triggered by track completion.
  Future<void> next({bool auto = false}) async {
    final s = state;

    if (auto && s.repeat == RepeatMode.one) {
      if (s.current != null) await _loadAndPlay(s.current!);
      return;
    }

    // Manual queue always has priority over the context.
    if (s.manualQueue.isNotEmpty) {
      final track = s.manualQueue.first;
      state = s.copyWith(
        manualQueue: s.manualQueue.sublist(1),
        fromManualQueue: true,
      );
      await _loadAndPlay(track);
      return;
    }

    final nextIndex = _nextContextIndex(s, wrap: s.repeat == RepeatMode.all);
    if (nextIndex == null) {
      // End of context, repeat off: stop at the end, keep track loaded.
      if (auto) {
        await _handler.pause();
        await _handler.seek(Duration.zero);
      }
      unawaited(_saveState());
      return;
    }
    state = state.copyWith(contextIndex: nextIndex, fromManualQueue: false);
    await _loadAndPlay(state.context[nextIndex]);
  }

  Future<void> previous() async {
    final s = state;
    if (s.current == null) return;

    // Past 3 seconds: restart the current track.
    if (_handler.position > const Duration(seconds: 3)) {
      await _handler.seek(Duration.zero);
      return;
    }

    if (s.fromManualQueue) {
      // Return to where the context left off.
      if (s.contextIndex >= 0 && s.contextIndex < s.context.length) {
        state = s.copyWith(fromManualQueue: false);
        await _loadAndPlay(s.context[s.contextIndex]);
        return;
      }
      await _handler.seek(Duration.zero);
      return;
    }

    final prevIndex = _previousContextIndex(
      s,
      wrap: s.repeat == RepeatMode.all,
    );
    if (prevIndex == null) {
      await _handler.seek(Duration.zero);
      return;
    }
    state = s.copyWith(contextIndex: prevIndex);
    await _loadAndPlay(state.context[prevIndex]);
  }

  void toggleShuffle() {
    final s = state;
    if (s.shuffle) {
      state = s.copyWith(shuffle: false, shuffleOrder: const []);
    } else {
      state = s.copyWith(
        shuffle: true,
        shuffleOrder: _makeShuffleOrder(
          s.context.length,
          s.contextIndex.clamp(0, max(0, s.context.length - 1)),
        ),
      );
    }
    unawaited(_saveState());
  }

  void cycleRepeat() {
    final next =
        RepeatMode.values[(state.repeat.index + 1) % RepeatMode.values.length];
    state = state.copyWith(repeat: next);
    unawaited(_saveState());
  }

  void playNextInQueue(Track track) {
    state = state.copyWith(manualQueue: [track, ...state.manualQueue]);
    unawaited(_saveState());
  }

  void addToQueue(Track track) {
    state = state.copyWith(manualQueue: [...state.manualQueue, track]);
    unawaited(_saveState());
  }

  void removeFromManualQueue(int index) {
    if (index < 0 || index >= state.manualQueue.length) return;
    final queue = List.of(state.manualQueue)..removeAt(index);
    state = state.copyWith(manualQueue: queue);
    unawaited(_saveState());
  }

  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  void reorderManualQueue(int oldIndex, int newIndex) {
    final queue = List.of(state.manualQueue);
    if (oldIndex < 0 || oldIndex >= queue.length) return;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex.clamp(0, queue.length), item);
    state = state.copyWith(manualQueue: queue);
    unawaited(_saveState());
  }

  /// Tap on a manual queue entry: play it now and drop it from the queue.
  Future<void> playManualQueueItem(int index) async {
    if (index < 0 || index >= state.manualQueue.length) return;
    final track = state.manualQueue[index];
    final queue = List.of(state.manualQueue)..removeAt(index);
    state = state.copyWith(manualQueue: queue, fromManualQueue: true);
    await _loadAndPlay(track);
  }

  /// Tap on an upcoming context entry: jump the context to it.
  Future<void> playContextTrack(Track track) async {
    final index = state.context.indexWhere((t) => t.id == track.id);
    if (index < 0) return;
    state = state.copyWith(contextIndex: index, fromManualQueue: false);
    await _loadAndPlay(track);
  }

  /// Called by the sleep timer when it fires. The app is killed straight
  /// after, so everything is awaited rather than left running: a fire-and-
  /// forget write would not survive the exit.
  Future<void> stopFromSleepTimer() async {
    await _handler.pause();
    await _flushListening();
    await _saveState();
    await _widgets.update(track: state.current, playing: false);
  }

  /// Drop a track everywhere it appears (after a library soft delete).
  void removeTrackFromQueues(int trackId) {
    final s = state;
    final contextIdx = s.context.indexWhere((t) => t.id == trackId);
    var next = s.copyWith(
      manualQueue: s.manualQueue.where((t) => t.id != trackId).toList(),
    );
    if (contextIdx >= 0) {
      final newContext = List.of(s.context)..removeAt(contextIdx);
      var newIndex = s.contextIndex;
      if (contextIdx < newIndex) newIndex -= 1;
      newIndex = newContext.isEmpty
          ? -1
          : newIndex.clamp(0, newContext.length - 1);
      next = next.copyWith(
        context: newContext,
        contextIndex: newIndex,
        shuffleOrder: next.shuffle && newContext.isNotEmpty
            ? _makeShuffleOrder(newContext.length, max(0, newIndex))
            : const [],
      );
    }
    state = next;
    unawaited(_saveState());
  }

  // ---------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------

  Future<void> restore() async {
    final saved = await _persistence.load();
    if (saved == null || saved.currentTrackId == null) return;

    final contextTracks = await _db.tracksByIds(saved.contextTrackIds);
    final manualTracks = await _db.tracksByIds(saved.manualQueueIds);
    final current = await _db.trackById(saved.currentTrackId!);
    if (current == null || current.isDeleted) return;

    var contextIndex = saved.contextIndex;
    if (contextIndex >= contextTracks.length) {
      contextIndex = contextTracks.isEmpty ? -1 : contextTracks.length - 1;
    }

    var shuffleOrder = saved.shuffleOrder;
    if (saved.shuffle && shuffleOrder.length != contextTracks.length) {
      shuffleOrder = _makeShuffleOrder(
        contextTracks.length,
        max(0, contextIndex),
      );
    }

    state = PlayerQueueState(
      current: current,
      fromManualQueue: saved.fromManualQueue,
      context: contextTracks,
      contextName: saved.contextName,
      contextIndex: contextIndex,
      manualQueue: manualTracks,
      shuffle: saved.shuffle,
      shuffleOrder: shuffleOrder,
      repeat: RepeatMode
          .values[saved.repeatIndex.clamp(0, RepeatMode.values.length - 1)],
    );

    unawaited(_widgets.update(track: current, playing: false));

    if (!await trackFileExists(current)) return;

    _playsBooked = 0;
    await _handler.loadTrack(current, autoPlay: false);
    final target = Duration(milliseconds: saved.positionMs);
    if (target > Duration.zero) {
      // Seek once the media is actually loaded.
      _handler.player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .then((_) => _handler.seek(target))
          .ignore();
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<void> _loadAndPlay(Track track) async {
    if (!await trackFileExists(track)) {
      ref.read(playerMessageProvider.notifier).state =
          'File missing: ${track.title} — skipped';
      // Avoid infinite loops when everything is missing.
      final anyLeft =
          state.manualQueue.isNotEmpty ||
          _nextContextIndex(state, wrap: false) != null;
      if (anyLeft) {
        await next();
      }
      return;
    }
    _playsBooked = 0;
    // Closes the outgoing track's session while it is still `state.current`,
    // so its time is booked against the right track.
    await _resetListening();
    state = state.copyWith(current: track);
    await _handler.loadTrack(track);
    unawaited(_saveState());
    unawaited(_widgets.update(track: track, playing: _handler.playing));
  }

  Future<void> _handleCompletion() async {
    // Sleep timer "end of current track" mode: stop here.
    final sleepTimer = ref.read(sleepTimerProvider);
    if (sleepTimer != null && sleepTimer.endOfTrack) {
      await ref.read(sleepTimerProvider.notifier).fireNow();
      return;
    }
    await next(auto: true);
  }

  int? _nextContextIndex(PlayerQueueState s, {required bool wrap}) {
    if (s.context.isEmpty) return null;
    if (s.fromManualQueue) {
      // Resume the context at the track it was paused on.
      return s.contextIndex >= 0 && s.contextIndex < s.context.length
          ? s.contextIndex
          : 0;
    }
    if (s.shuffle && s.shuffleOrder.length == s.context.length) {
      final pos = s.shuffleOrder.indexOf(s.contextIndex);
      if (pos < 0) return s.shuffleOrder.isEmpty ? null : s.shuffleOrder[0];
      if (pos + 1 < s.shuffleOrder.length) return s.shuffleOrder[pos + 1];
      return wrap ? s.shuffleOrder[0] : null;
    }
    if (s.contextIndex + 1 < s.context.length) return s.contextIndex + 1;
    return wrap ? 0 : null;
  }

  int? _previousContextIndex(PlayerQueueState s, {required bool wrap}) {
    if (s.context.isEmpty) return null;
    if (s.shuffle && s.shuffleOrder.length == s.context.length) {
      final pos = s.shuffleOrder.indexOf(s.contextIndex);
      if (pos > 0) return s.shuffleOrder[pos - 1];
      return wrap ? s.shuffleOrder.last : null;
    }
    if (s.contextIndex > 0) return s.contextIndex - 1;
    return wrap ? s.context.length - 1 : null;
  }

  List<int> _makeShuffleOrder(int length, int firstIndex) {
    if (length <= 0) return const [];
    final rest = [
      for (var i = 0; i < length; i++)
        if (i != firstIndex) i,
    ]..shuffle(_random);
    return [firstIndex, ...rest];
  }

  // Both stats come off the same measurement: what the [ListeningMeter] saw
  // actually play. Sessions store the time spent listening, so a track at
  // 0.75× is worth more of it than the same track at 1.5×; the play threshold
  // uses the recording's own timeline, so a track counts as played whatever
  // speed it ran at. A play is booked once a quarter of the track (capped at
  // [scrobbleCap]) has gone past — deliberately *not* when the position marker
  // crosses that mark, which a scrub or an mpv position re-emit after a
  // filter-chain rebuild would also do.
  void _onPosition(Duration position) {
    final track = state.current;
    if (track == null) return;

    final duration = track.durationMs > 0
        ? Duration(milliseconds: track.durationMs)
        : _handler.player.state.duration;
    if (duration <= Duration.zero) return;

    final added = _meter.add(
      position: position,
      at: DateTime.now(),
      playing: _handler.playing,
      rate: _handler.rate,
    );
    if (added > 0 &&
        DateTime.now().difference(_lastListenFlush) >= _listenFlushInterval) {
      unawaited(_flushListening());
    }

    // A track looping under the same load (seek back to the start, or a long
    // mix played through twice) books another play every further track-length
    // that goes past, so a replay still counts while a scrub cannot fake one.
    final nextPlayAtMs =
        scrobbleThresholdMs(duration) + _playsBooked * duration.inMilliseconds;
    if (_meter.heardMs >= nextPlayAtMs) {
      _playsBooked++;
      unawaited(_db.recordPlay(track.id));
    }

    unawaited(_persistence.saveThrottled(_snapshot()));
  }

  // ---------------------------------------------------------------------
  // Measured listening time (Stats → "Time listened")
  // ---------------------------------------------------------------------

  /// Persists the running total. Idempotent — it writes an absolute value, so
  /// calling it more often than needed only costs a write.
  Future<void> _flushListening() async {
    _lastListenFlush = DateTime.now();
    final track = state.current;
    final listenedMs = _meter.listenedMs;
    if (track == null || listenedMs == _savedListenedMs) return;
    // Ignore stretches too short to be listening (a tap through a queue).
    if (listenedMs < 1000) return;

    _listenSessionId ??= await _db.startListeningSession(track.id);
    _savedListenedMs = listenedMs;
    await _db.saveListenedMs(_listenSessionId!, listenedMs);
  }

  /// Closes the current session and starts counting again for the next track.
  Future<void> _resetListening() async {
    await _flushListening();
    _listenSessionId = null;
    _savedListenedMs = 0;
    _meter.reset();
  }

  PersistedPlayback _snapshot() {
    final s = state;
    return PersistedPlayback(
      currentTrackId: s.current?.id,
      positionMs: _handler.position.inMilliseconds,
      contextTrackIds: [for (final t in s.context) t.id],
      contextName: s.contextName,
      manualQueueIds: [for (final t in s.manualQueue) t.id],
      contextIndex: s.contextIndex,
      shuffle: s.shuffle,
      shuffleOrder: s.shuffleOrder,
      repeatIndex: s.repeat.index,
      fromManualQueue: s.fromManualQueue,
    );
  }

  Future<void> _saveState() => _persistence.save(_snapshot());
}

// ---------------------------------------------------------------------------
// Playback status streams (kept out of PlayerQueueState to avoid rebuilding
// the whole UI every 100 ms).
// ---------------------------------------------------------------------------

final playingProvider = StreamProvider<bool>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.player.stream.playing;
});

final positionProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.player.stream.position;
});

final durationProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.player.stream.duration;
});
