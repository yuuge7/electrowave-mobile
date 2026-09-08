import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart' as type;
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/track_context_menu.dart';
import '../../library/providers/browse_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/services/settings_persistence.dart';
import '../providers/accent_providers.dart';
import '../providers/player_providers.dart';
import '../providers/sleep_timer_provider.dart';
import 'sleep_timer_sheet.dart';

/// The full transport.
///
/// Three things drive the layout. The counter is the largest element on the
/// screen, because on a deck it is: it is the one number you look at while
/// listening. Everything is left-aligned to a single margin instead of
/// centred, so the eye reads title → artist → counter → controls down one
/// edge. And the next track is visible without leaving, since "what is
/// coming" is the second question anyone has.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final playerTrack = state.current;
    final controller = ref.read(playerControllerProvider.notifier);

    if (playerTrack == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyStateView(
          icon: Icons.music_note_outlined,
          title: 'Nothing playing',
          message: 'Pick a track from your library and it will show up here.',
        ),
      );
    }

    // The player holds a snapshot; watch the row so favorite/tag edits show
    // up here immediately.
    final track =
        ref.watch(trackStreamProvider(playerTrack.id)).value ?? playerTrack;

    final playing = ref.watch(playingProvider).value ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final streamDuration = ref.watch(durationProvider).value ?? Duration.zero;
    final duration = streamDuration > Duration.zero
        ? streamDuration
        : Duration(milliseconds: track.durationMs);

    final sleepTimer = ref.watch(sleepTimerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.deck;
    final accent =
        ref.watch(currentAccentProvider)?.resolve(scheme) ?? tokens.signal;
    final backdrop =
        ref.watch(currentAccentProvider)?.backdrop(scheme) ?? scheme.surface;

    final upNext = state.manualQueue.isNotEmpty
        ? state.manualQueue.first
        : (state.upcomingContext.isNotEmpty
              ? state.upcomingContext.first
              : null);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // The bar is transparent over an art-tinted gradient, so Flutter
        // cannot infer the status-bar icon colour from a background it does
        // not have — on the light theme the clock and battery came out white
        // on cream. State it from the theme instead.
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          tooltip: 'Close player',
          onPressed: () => context.pop(),
        ),
        title: PanelLabel(
          'Playing from · '
          '${state.contextName.isEmpty ? 'Queue' : state.contextName}',
        ),
        actions: [
          IconButton(
            icon: Icon(
              track.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: track.isFavorite ? tokens.signal : null,
            ),
            tooltip: track.isFavorite ? 'Remove from favourites' : 'Favourite',
            onPressed: () {
              HapticFeedback.selectionClick();
              ref
                  .read(databaseProvider)
                  .setFavorite(track.id, !track.isFavorite);
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More actions',
            onPressed: () => showTrackContextMenu(context, track),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backdrop, scheme.surface],
            stops: const [0, 0.62],
          ),
        ),
        // A downward flick anywhere dismisses, matching the chevron.
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 260) context.pop();
          },
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  // The art takes whatever the fixed furniture below does
                  // not, rather than a fraction of the screen with spacers
                  // around it — that left a dead band between the cover and
                  // the title on tall phones, and squeezed the counter on
                  // short ones.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                      // Slack belongs above the cover, not between the cover
                      // and the title that names it.
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _SwipeableArt(
                            track: track,
                            onNext: controller.next,
                            onPrevious: controller.previous,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Title, counter and keys are fixed furniture that grows
                  // with the text scale, while the cover above absorbs the
                  // slack. Past a large accessibility scale on a short phone
                  // there is no slack left and the column ran off the bottom,
                  // so cap the furniture and scale it down to fit instead.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.72,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.album.isEmpty
                                    ? track.artist
                                    : '${track.artist} · ${track.album}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              _ChainStatus(
                                settings: settings,
                                sleepTimer: sleepTimer,
                              ),
                              const SizedBox(height: 18),
                              _Transport(
                                position: position,
                                duration: duration,
                                accent: accent,
                                onSeek: controller.seek,
                              ),
                              const SizedBox(height: 6),
                              _Controls(
                                playing: playing,
                                state: state,
                                // Deliberately the brand signal, not the
                                // cover's accent: a control that changes
                                // colour with the artwork can land on red,
                                // and a red play button reads as "stop".
                                accent: tokens.signal,
                                controller: controller,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _UpNext(
                    track: upNext,
                    isManual: state.manualQueue.isNotEmpty,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Art
// ---------------------------------------------------------------------------

/// Horizontal drags change track, which is the gesture every player has
/// trained people to expect and the only one that reaches the queue without
/// a button. The cover slides in from the side it came from.
class _SwipeableArt extends StatelessWidget {
  const _SwipeableArt({
    required this.track,
    required this.onNext,
    required this.onPrevious,
  });

  final Track track;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 240) return;
        HapticFeedback.selectionClick();
        velocity < 0 ? onNext() : onPrevious();
      },
      child: Hero(
        tag: 'now-playing-art',
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: LayoutBuilder(
            key: ValueKey(track.id),
            builder: (context, constraints) => ArtThumb(
              artPath: track.albumArtPath,
              size: double.infinity,
              decodeWidth: constraints.maxWidth,
              borderRadius: 12,
              seed: track.album.isNotEmpty ? track.album : track.title,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chain status
// ---------------------------------------------------------------------------

/// What the audio chain is doing to this track right now.
///
/// These were all invisible while listening, which made one of them look like
/// a bug: with skip-silence on, tracks end before their tagged length and
/// nothing said why.
class _ChainStatus extends ConsumerWidget {
  const _ChainStatus({required this.settings, required this.sleepTimer});

  final AppSettings settings;
  final SleepTimerState? sleepTimer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = <Widget>[
      // Always present, at 1× as much as at 1.75×. Speed is the setting this
      // player gets reached for most and it used to live three taps away in
      // Settings; a chip that only appears once you have already changed it
      // is no way to change it.
      StatusChip(
        label: '${formatPlaybackRate(settings.playbackRate)}×',
        semanticLabel:
            'Playback speed, ${formatPlaybackRate(settings.playbackRate)} '
            'times. Change it',
        icon: Icons.speed_rounded,
        tone: settings.playbackRate == 1.0
            ? StatusTone.neutral
            : StatusTone.signal,
        onTap: () => showAppSheet<void>(
          context,
          builder: (_) => const _SpeedSheet(),
        ),
      ),
      if (settings.skipSilence)
        const StatusChip(
          label: 'Silence trimmed',
          icon: Icons.content_cut_rounded,
        ),
      if (settings.eqEnabled)
        StatusChip(
          label: 'EQ',
          icon: Icons.graphic_eq_rounded,
          onTap: () => context.push('/equalizer'),
        ),
      // Always present, unlike the rest: the others report a setting that is
      // already on, this one is also the only way to reach the timer from the
      // player. Showing it only while running left no way to start it.
      StatusChip(
        label: switch (sleepTimer) {
          null => 'Sleep timer',
          final t when t.endOfTrack => 'Sleep · end of track',
          final t => 'Sleep · ${formatDuration(t.remaining)}',
        },
        icon: sleepTimer == null
            ? Icons.bedtime_outlined
            : Icons.bedtime_rounded,
        tone: sleepTimer == null ? StatusTone.neutral : StatusTone.peak,
        onTap: () => showSleepTimerSheet(context),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }
}

/// The speed dial behind the chip.
///
/// A dial, not a menu: the rate applies as it changes and the sheet stays
/// open, so you nudge it against the track you can hear rather than guessing
/// a value, closing, and coming back. The presets are the jumps; the keys
/// either side of the readout are the fine adjustment between them.
class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  static const List<double> _presets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const double _step = 0.05;
  static const double _min = 0.5;
  static const double _max = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(
      settingsControllerProvider.select((s) => s.playbackRate),
    );
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final normal = rate == 1.0;

    // Rounded through two decimals on the way in: 1.0 - 0.05 is not exactly
    // 0.95 in binary, and without this the readout drifts to "0.9500000001"
    // after a few taps.
    void setRate(double value) {
      final next = double.parse(
        value.clamp(_min, _max).toStringAsFixed(2),
      );
      if (next == rate) return;
      HapticFeedback.selectionClick();
      ref.read(settingsControllerProvider.notifier).setPlaybackRate(next);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Playback speed',
          trailing: normal
              ? null
              : TextButton(
                  onPressed: () => setRate(1),
                  child: const Text('Reset'),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
          child: Row(
            children: [
              _StepKey(
                icon: Icons.remove_rounded,
                tooltip: 'Slower',
                onPressed: rate <= _min ? null : () => setRate(rate - _step),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${formatPlaybackRate(rate)}×',
                    style: type
                        .counter(44)
                        .copyWith(
                          color: normal ? scheme.onSurface : tokens.signal,
                        ),
                    semanticsLabel: 'Playback speed '
                        '${formatPlaybackRate(rate)} times',
                  ),
                ),
              ),
              _StepKey(
                icon: Icons.add_rounded,
                tooltip: 'Faster',
                onPressed: rate >= _max ? null : () => setRate(rate + _step),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _presets)
                _PresetKey(
                  value: value,
                  selected: value == rate,
                  onTap: () => setRate(value),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One of the two keys either side of the speed readout.
class _StepKey extends StatelessWidget {
  const _StepKey({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      icon: Icon(icon),
      iconSize: 22,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

/// A speed you can land on in one tap. Selected keys take the signal colour,
/// the same way every other live-state marker in the app does.
class _PresetKey extends StatelessWidget {
  const _PresetKey({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? tokens.signal.withValues(alpha: 0.6)
                  : scheme.outline.withValues(alpha: 0.4),
            ),
            color: selected
                ? tokens.signal.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Text(
            '${formatPlaybackRate(value)}×',
            style: type
                .instrument(12, weight: 500)
                .copyWith(
                  color: selected ? tokens.signal : scheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transport: the counter and the rule beneath it
// ---------------------------------------------------------------------------

class _Transport extends StatefulWidget {
  const _Transport({
    required this.position,
    required this.duration,
    required this.accent,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Color accent;
  final ValueChanged<Duration> onSeek;

  @override
  State<_Transport> createState() => _TransportState();
}

class _TransportState extends State<_Transport> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.toDouble();
    final valueMs = (_dragMs ?? widget.position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs > 0 ? maxMs : 1.0);
    final shown = Duration(milliseconds: valueMs.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TransportCounter(
          position: shown,
          duration: widget.duration,
          format: formatDuration,
          color: widget.accent,
          size: 40,
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: widget.accent,
            thumbColor: widget.accent,
            overlayColor: widget.accent.withValues(alpha: 0.14),
            padding: EdgeInsets.zero,
          ),
          child: Slider(
            value: maxMs > 0 ? valueMs : 0,
            max: maxMs > 0 ? maxMs : 1,
            // Without this a screen reader announces the raw millisecond
            // double ("1.0 to 214000.0"), which is unusable.
            semanticFormatterCallback: (value) =>
                formatDuration(Duration(milliseconds: value.round())),
            onChanged: maxMs > 0
                ? (value) => setState(() => _dragMs = value)
                : null,
            onChangeEnd: maxMs > 0
                ? (value) {
                    widget.onSeek(Duration(milliseconds: value.round()));
                    setState(() => _dragMs = null);
                  }
                : null,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.state,
    required this.accent,
    required this.controller,
  });

  final bool playing;
  final PlayerQueueState state;
  final Color accent;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final idle = scheme.onSurfaceVariant;

    // Five fixed-size keys do not fit the 320dp phones at their design size,
    // and the row overflowed rather than giving. Below the width the keys
    // want, the whole transport scales down together — at or above it, the
    // row spreads to the margins exactly as before.
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.shuffle_rounded),
                  color: state.shuffle ? accent : idle,
                  tooltip: state.shuffle ? 'Shuffle on' : 'Shuffle off',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    controller.toggleShuffle();
                  },
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous_rounded),
                  color: scheme.onSurface,
                  tooltip: 'Previous track',
                  onPressed: controller.previous,
                ),
                // The one filled control on the screen. Square-cornered,
                // because the rest of the app is, and sized for a thumb.
                // The lit key. On a deck the transport is neutral hardware
                // and the counter is the illuminated part; a solid accent
                // block here was out-shouting the counter, which is what
                // this screen is built around. Backlit rather than filled
                // keeps it unmistakably primary without taking the eye
                // first.
                Material(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: 0.16),
                    scheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      controller.togglePlayPause();
                    },
                    child: Container(
                      width: 74,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                        color: accent,
                        semanticLabel: playing ? 'Pause' : 'Play',
                      ),
                    ),
                  ),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next_rounded),
                  color: scheme.onSurface,
                  tooltip: 'Next track',
                  onPressed: () => controller.next(),
                ),
                IconButton(
                  icon: Icon(
                    state.repeat == RepeatMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                  ),
                  color: state.repeat != RepeatMode.off ? accent : idle,
                  tooltip: switch (state.repeat) {
                    RepeatMode.off => 'Repeat off',
                    RepeatMode.all => 'Repeat all',
                    RepeatMode.one => 'Repeat one',
                  },
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    controller.cycleRepeat();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Up next
// ---------------------------------------------------------------------------

/// What plays after this one, without leaving the screen. Replaces the Queue
/// button: the button asked you to go and look, this answers the question.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.track, required this.isManual});

  final Track? track;
  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.deck;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/queue'),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.hairline)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PanelLabel(isManual ? 'Up next · queued' : 'Up next'),
                    const SizedBox(height: 6),
                    Text(
                      track == null
                          ? 'Nothing queued'
                          : '${track!.title} — ${track!.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: track == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
                semanticLabel: 'Open the queue',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
