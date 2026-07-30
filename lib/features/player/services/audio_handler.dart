import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../../../core/database/database.dart';

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
    _idleStopTimer =
        playing ? null : Timer(_idleStopTimeout, () => unawaited(stop()));
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
            await pause();
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (_ducked) {
              _ducked = false;
              await _player.setVolume(_volumeBeforeDuck);
            }
          case AudioInterruptionType.pause:
            if (_playingBeforeInterruption) await play();
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Headphones unplugged: pause.
    session.becomingNoisyEventStream.listen((_) => pause());
  }

  void _wireStreams() {
    // No broadcast on position ticks: the MediaSession extrapolates position
    // from (updatePosition, updateTime, speed), so per-tick updates would
    // only churn the platform channel and notification several times a
    // second for the whole play session.
    _player.stream.playing.listen((playing) {
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
    if (autoPlay) await play();
  }

  Future<bool> activateSession() async {
    return await _session?.setActive(true) ?? true;
  }

  @override
  Future<void> play() async {
    await activateSession();
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    // Position broadcasts are event-driven, so push the new anchor point.
    _broadcast();
  }

  @override
  Future<void> stop() async {
    _idleStopTimer?.cancel();
    _idleStopTimer = null;
    await _player.pause();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkipToNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipToPrevious?.call();

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  double get volume => _player.state.volume;

  Duration get position => _player.state.position;

  bool get playing => _player.state.playing;

  Future<void> dispose() {
    _idleStopTimer?.cancel();
    return _player.dispose();
  }
}

/// Missing-file guard: returns true when the track's file still exists.
Future<bool> trackFileExists(Track track) => File(track.filePath).exists();
