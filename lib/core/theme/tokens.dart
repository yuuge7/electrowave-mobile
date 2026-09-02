import 'package:flutter/material.dart';

/// Roles Material's [ColorScheme] has no name for.
///
/// The rule this encodes: **teal is signal**. It marks what is live right
/// now — the track that is playing, the position inside it, the destination
/// you are on — and nothing else. Section headings, chips at rest, icons and
/// dividers are achromatic. Spraying the accent over every affordance is what
/// makes an interface read as a theme applied to a template rather than as a
/// designed thing, and it also destroys the accent's only real job: telling
/// you where the sound is.
@immutable
class DeckTokens extends ThemeExtension<DeckTokens> {
  const DeckTokens({
    required this.signal,
    required this.onSignal,
    required this.signalDim,
    required this.meterTrack,
    required this.peak,
    required this.panel,
    required this.hairline,
    required this.recessed,
  });

  /// Live state: playback position, the current track, the active destination.
  final Color signal;
  final Color onSignal;

  /// Signal at rest — a track that has been played, a paused position.
  final Color signalDim;

  /// The unfilled part of any meter or seek rule.
  final Color meterTrack;

  /// Attention that is not an error: a peak, a missing file, a warning chip.
  /// Amber, the way a deck's peak indicator is amber.
  final Color peak;

  /// Engraved panel labels — the small uppercase type naming a region.
  final Color panel;

  /// 1px structural rule. Deliberately dimmer than [ColorScheme.outline],
  /// which Material sizes for form-field borders.
  final Color hairline;

  /// Inset wells: the seek bar's channel, an art placeholder, a meter slot.
  final Color recessed;

  @override
  DeckTokens copyWith({
    Color? signal,
    Color? onSignal,
    Color? signalDim,
    Color? meterTrack,
    Color? peak,
    Color? panel,
    Color? hairline,
    Color? recessed,
  }) {
    return DeckTokens(
      signal: signal ?? this.signal,
      onSignal: onSignal ?? this.onSignal,
      signalDim: signalDim ?? this.signalDim,
      meterTrack: meterTrack ?? this.meterTrack,
      peak: peak ?? this.peak,
      panel: panel ?? this.panel,
      hairline: hairline ?? this.hairline,
      recessed: recessed ?? this.recessed,
    );
  }

  @override
  DeckTokens lerp(ThemeExtension<DeckTokens>? other, double t) {
    if (other is! DeckTokens) return this;
    return DeckTokens(
      signal: Color.lerp(signal, other.signal, t)!,
      onSignal: Color.lerp(onSignal, other.onSignal, t)!,
      signalDim: Color.lerp(signalDim, other.signalDim, t)!,
      meterTrack: Color.lerp(meterTrack, other.meterTrack, t)!,
      peak: Color.lerp(peak, other.peak, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      recessed: Color.lerp(recessed, other.recessed, t)!,
    );
  }
}

extension DeckTokensLookup on BuildContext {
  DeckTokens get deck => Theme.of(this).extension<DeckTokens>()!;
}
