import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart' as type;

/// The small shared vocabulary the interface is built from.
///
/// There is one recurring form: a 2px horizontal rule that fills from the
/// left to show a position. It is the mini player's progress, the seek bar's
/// channel, and the marker over the active navigation destination. Reusing
/// one element at three scales is what makes the app look like a single
/// object instead of a set of screens.

// ---------------------------------------------------------------------------
// Panel label
// ---------------------------------------------------------------------------

/// The engraved label that names a region: "PLAYING FROM", "UP NEXT",
/// "TOP TRACKS". Uppercases its own text so call sites read normally.
class PanelLabel extends StatelessWidget {
  const PanelLabel(
    this.text, {
    super.key,
    this.color,
    this.size = 10,
    this.trailing,
  });

  final String text;
  final Color? color;
  final double size;

  /// Optional value set hard against the label — a count, a total.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: type.panelLabel(size: size).copyWith(
            color: color ?? context.deck.panel,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (trailing == null) return label;
    return Row(
      children: [
        Flexible(child: label),
        const SizedBox(width: 10),
        trailing!,
      ],
    );
  }
}

/// A panel label with the hairline that separates it from what it names.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 8),
  });

  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: PanelLabel(text)),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signal rule
// ---------------------------------------------------------------------------

/// The recurring position rule. [value] is 0..1, or null for an idle channel.
class SignalRule extends StatelessWidget {
  const SignalRule({
    super.key,
    required this.value,
    this.height = 2,
    this.color,
    this.trackColor,
    this.radius = 0,
  });

  final double? value;
  final double height;
  final Color? color;
  final Color? trackColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor ?? tokens.meterTrack),
            if (value != null)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value!.clamp(0.0, 1.0),
                child: ColoredBox(color: color ?? tokens.signal),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transport counter
// ---------------------------------------------------------------------------

/// The signature: a deck's counter. Elapsed time large, the other figure
/// small beside it. Tapping swaps the small figure between total and
/// remaining, which is the first thing anyone reaches for on a player.
class TransportCounter extends StatefulWidget {
  const TransportCounter({
    super.key,
    required this.position,
    required this.duration,
    required this.format,
    this.color,
    this.size = 46,
  });

  final Duration position;
  final Duration duration;
  final String Function(Duration) format;
  final Color? color;
  final double size;

  @override
  State<TransportCounter> createState() => _TransportCounterState();
}

class _TransportCounterState extends State<TransportCounter> {
  bool _showRemaining = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final remaining = widget.duration - widget.position;
    final secondary = _showRemaining
        ? '-${widget.format(remaining.isNegative ? Duration.zero : remaining)}'
        : widget.format(widget.duration);

    return Semantics(
      label: 'Elapsed ${widget.format(widget.position)} of '
          '${widget.format(widget.duration)}',
      button: true,
      hint: _showRemaining ? 'Show total length' : 'Show time remaining',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showRemaining = !_showRemaining),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              widget.format(widget.position),
              style: type.counter(widget.size).copyWith(
                color: widget.color ?? tokens.signal,
              ),
            ),
            // A hairline slash instead of a gap: the two figures are one
            // reading, and the old size jump made the second look like a
            // footnote rather than the other half of it.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.size * 0.18),
              child: Text(
                '/',
                style: type.counter(widget.size * 0.52, weight: 300).copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
            Text(
              secondary,
              style: type.counter(widget.size * 0.52, weight: 500).copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

/// A small readout for something the playback chain is actually doing —
/// a non-1.0 rate, silence trimming, an active EQ. These are real effects
/// applied to the audio, and until now none of them were visible while
/// listening.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.deck;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      StatusTone.neutral => scheme.onSurfaceVariant,
      StatusTone.signal => tokens.signal,
      StatusTone.peak => tokens.peak,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label.toUpperCase(),
              style: type.panelLabel(size: 9.5).copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusTone { neutral, signal, peak }
