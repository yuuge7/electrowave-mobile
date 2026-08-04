import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../../../core/database/database.dart';
import '../../settings/services/settings_persistence.dart';

/// Bridges media_kit playback to Android via audio_service:
/// media-style notification, lock screen controls, headset/bluetooth
/// buttons, and audio focus handling (through audio_session).
class ElectrowaveAudioHandler extends BaseAudioHandler with SeekHandler {
  ElectrowaveAudioHandler() {
    _player = Player();
    _wireStreams();
    unawaited(_configureSession());
  }

  late final Player _player;
  Player get player => _player;

  /// Set by the player controller; invoked from notification / media buttons.
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  /// Fired when the current file finished playing.
  Future<void> Function()? onCompleted;

  AudioSession? _session;
  bool _playingBeforeInterruption = false;
  double _volumeBeforeDuck = 100;
  bool _ducked = false;

  /// With androidStopForegroundOnPause: false the service keeps its wake
  /// lock while paused; stop it after a long pause so a forgotten paused
  /// player doesn't hold the CPU awake overnight. Playback state is
  /// persisted, so this is always safe.
  Timer? _idleStopTimer;
  static const _idleStopTimeout = Duration(minutes: 15);

  void _restartIdleStopTimer({required bool playing}) {
    _idleStopTimer?.cancel();
    if (playing) {
      _idleStopTimer = null;
      return;
    }
    _idleStopTimer = Timer(_idleStopTimeout, () {
      // mpv delivers its end-of-file playing=false *after* onCompleted has
      // already opened and started the next track, so a `false` event is not
      // proof the player is idle 15 minutes later. Stopping the service on a
      // stale event kills playback mid-song and tears down the notification
      // for good — re-check live state before acting on it.
      if (_player.state.playing) {
        _restartIdleStopTimer(playing: true);
        return;
      }
      unawaited(stop());
    });
  }

  /// "Stop after N without the user touching anything" (Settings → Playback).
  /// Independent of [_idleStopTimer], which only covers a player left paused:
  /// this one fires while audio is still playing, on the assumption nobody is
  /// listening any more. Null when the setting is off.
  Timer? _inactivityTimer;
  Duration? _inactivityTimeout;

  /// Applied from the settings controller; null disables the check.
  void setInactivityTimeout(Duration? timeout) {
    _inactivityTimeout = timeout;
    _restartInactivityTimer();
  }

  /// Push the auto-stop deadline back. Called for anything the user actually
  /// did: a touch anywhere in the app, a notification / widget / headset
  /// control, a media button. Deliberately *not* called for automatic track
  /// advances or interruption resumes — those aren't the user being present.
  void noteUserActivity() => _restartInactivityTimer();

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    final timeout = _inactivityTimeout;
    if (timeout == null) {
      _inactivityTimer = null;
      return;
    }
    _inactivityTimer = Timer(timeout, () {
      // Already stopped or paused: _idleStopTimer owns that case, and firing
      // here would only race it.
      if (!_player.state.playing) return;
      unawaited(stop());
    });
  }

  Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    _session = session;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) async {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _volumeBeforeDuck = _player.state.volume;
            _ducked = true;
            await _player.setVolume(_volumeBeforeDuck * 0.3);
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _playingBeforeInterruption = _player.state.playing;
            await _player.pause();
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (_ducked) {
              _ducked = false;
              await _player.setVolume(_volumeBeforeDuck);
            }
          // `unknown` covers transient focus loss (a navigation prompt, a
          // notification sound). Treated like `pause`: without a resume here
          // a momentary interruption silences playback permanently.
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_playingBeforeInterruption) await _resumePlayback();
            _playingBeforeInterruption = false;
        }
      }
    });

    // Headphones unplugged: pause.
    session.becomingNoisyEventStream.listen((_) => _player.pause());
  }

  void _wireStreams() {
    // No broadcast on position ticks: the MediaSession extrapolates position
    // from (updatePosition, updateTime, speed), so per-tick updates would
    // only churn the platform channel and notification several times a
    // second for the whole play session.
    // The event value is deliberately ignored: mpv's end-of-file
    // playing=false can arrive after the next track is already playing, and
    // acting on that stale value leaves the notification stuck on a Play
    // button. `_player.state` is current by the time the event is delivered.
    _player.stream.playing.listen((_) {
      final playing = _player.state.playing;
      _broadcast(playing: playing);
      _restartIdleStopTimer(playing: playing);
    });
    _player.stream.buffering.listen((_) => _broadcast());
    _player.stream.duration.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration > Duration.zero) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
    _player.stream.completed.listen((completed) async {
      if (completed) await onCompleted?.call();
    });
  }

  /// audio_service's MediaControl.stop draws a filled square; the media
  /// notification convention is a close (X) affordance.
  static const _closeControl = MediaControl(
    androidIcon: 'drawable/ic_notification_close',
    label: 'Close',
    action: MediaAction.stop,
  );

  void _broadcast({bool? playing}) {
    final isPlaying = playing ?? _player.state.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _closeControl,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _player.state.buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: _player.state.position,
      speed: _player.state.rate,
    ));
  }

  /// Load [track] into the player and publish it to the media notification.
  Future<void> loadTrack(Track track, {bool autoPlay = true}) async {
    mediaItem.add(MediaItem(
      id: track.filePath,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: Duration(milliseconds: track.durationMs),
      artUri: track.albumArtPath != null && track.albumArtPath!.isNotEmpty
          ? Uri.file(track.albumArtPath!)
          : null,
    ));
    await _player.open(Media(track.filePath), play: false);
    if (_desiredRate != 1.0) await _player.setRate(_desiredRate);
    if (autoPlay) await _resumePlayback();
  }

  Future<bool> activateSession() async {
    return await _session?.setActive(true) ?? true;
  }

  /// Start audio without treating it as user activity — auto-advance to the
  /// next track and resume-after-interruption both land here.
  Future<void> _resumePlayback() async {
    await activateSession();
    await _player.play();
  }

  @override
  Future<void> play() async {
    noteUserActivity();
    await _resumePlayback();
  }

  @override
  Future<void> pause() {
    noteUserActivity();
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    noteUserActivity();
    await _player.seek(position);
    // Position broadcasts are event-driven, so push the new anchor point.
    _broadcast();
  }

  @override
  Future<void> stop() async {
    _idleStopTimer?.cancel();
    _idleStopTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await _player.pause();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    noteUserActivity();
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    noteUserActivity();
    await onSkipToPrevious?.call();
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  double get volume => _player.state.volume;

  /// Playback speed. Broadcast so the notification's position extrapolation
  /// stays in step with the audio.
  Future<void> setRate(double rate) async {
    _desiredRate = rate;
    await _player.setRate(rate);
    _broadcast();
  }

  double get rate => _player.state.rate;

  /// Remembered so it can be re-applied after every [loadTrack] — mpv resets
  /// speed when a new file is opened.
  double _desiredRate = 1.0;

  // -------------------------------------------------------------------------
  // mpv-level audio processing
  // -------------------------------------------------------------------------
  //
  // media_kit doesn't expose the Android audio session id, so the platform
  // AudioEffect API (Equalizer/BassBoost) isn't reachable. Instead these drive
  // libmpv's own filter chain and ReplayGain support, which also keeps the
  // behaviour identical across platforms.

  NativePlayer? get _native {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// Rebuild the `af` filter chain from [settings]. Passing an empty chain
  /// clears any filters, so a disabled/flat EQ costs nothing at runtime.
  Future<void> applyAudioSettings(AppSettings settings) async {
    final native = _native;
    if (native == null) return;

    final filters = <String>[];
    if (settings.eqEnabled) {
      for (var i = 0; i < kEqBandFrequencies.length; i++) {
        final gain = i < settings.eqGainsDb.length ? settings.eqGainsDb[i] : 0.0;
        // Skip inaudible bands to keep the chain short.
        if (gain.abs() < 0.1) continue;
        filters.add(
          'equalizer=f=${kEqBandFrequencies[i]}:t=o:w=2'
          ':g=${gain.toStringAsFixed(1)}',
        );
      }
    }

    try {
      await native.setProperty('af', filters.join(','));
      await native.setProperty('replaygain', switch (settings.replayGain) {
        ReplayGainMode.off => 'no',
        ReplayGainMode.track => 'track',
        ReplayGainMode.album => 'album',
      });
    } catch (_) {
      // An unsupported filter or property must not take playback down.
    }
  }

  Duration get position => _player.state.position;

  bool get playing => _player.state.playing;

  Future<void> dispose() {
    _idleStopTimer?.cancel();
    _inactivityTimer?.cancel();
    return _player.dispose();
  }
}

/// Missing-file guard: returns true when the track's file still exists.
Future<bool> trackFileExists(Track track) => File(track.filePath).exists();
