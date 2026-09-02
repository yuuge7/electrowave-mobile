
import 'package:flutter/material.dart';

/// Two voices.
///
/// **Archivo** carries everything a person reads: titles, track names, body.
/// It is a grotesque with real width and weight axes, so the scale is built
/// from variations rather than from separate files.
///
/// **Martian Mono** is the instrument voice, and it is deliberately rationed
/// to two jobs: the transport counter on Now Playing, and the small engraved
/// panel labels that name a region ("PLAYING FROM", "UP NEXT"). Using it for
/// body text would turn a deliberate accent into a texture.
const String kTextFamily = 'Archivo';
const String kInstrumentFamily = 'MartianMono';

/// Durations, counters, play counts and byte sizes are everywhere here, and
/// several tick live. Proportional figures make the text beside them jump on
/// every digit change, so every style in the app is tabular.
const List<FontFeature> kFigures = [FontFeature.tabularFigures()];

/// Variable-axis weight. Flutter picks the asset by family, then renders the
/// axis — so `fontWeight` alone would leave every style at the file's default.
/// Both are set: the variation does the work, the weight keeps fallback fonts
/// and synthetic bolding sensible.
List<FontVariation> _wght(double value) => [FontVariation('wght', value)];

FontWeight _nearest(double value) {
  final index = ((value / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[index];
}

TextStyle text(
  double size, {
  double weight = 400,
  double? tracking,
  double height = 1.25,
  double? width,
}) {
  return TextStyle(
    fontFamily: kTextFamily,
    fontSize: size,
    height: height,
    letterSpacing: tracking,
    fontWeight: _nearest(weight),
    fontVariations: [
      ..._wght(weight),
      if (width != null) FontVariation('wdth', width),
    ],
    fontFeatures: kFigures,
  );
}

TextStyle instrument(
  double size, {
  double weight = 400,
  double tracking = 0,
  double height = 1.1,
  double width = 100,
}) {
  return TextStyle(
    fontFamily: kInstrumentFamily,
    fontSize: size,
    height: height,
    letterSpacing: tracking,
    fontWeight: _nearest(weight),
    fontVariations: [..._wght(weight), FontVariation('wdth', width)],
    fontFeatures: kFigures,
  );
}

/// Engraved panel label: the small, wide-tracked, uppercase type that names a
/// region on a piece of hardware. Callers pass the text already uppercased so
/// the string in the widget tree reads the way it renders.
TextStyle panelLabel({double size = 10}) => instrument(
      size,
      weight: 600,
      tracking: 1.6,
      width: 87.5,
    );

/// The transport counter — the one piece of type this app should be
/// remembered by.
///
/// Set in Archivo rather than the mono: Martian Mono's slashed zero is the
/// loudest glyph in the family, and at counter size it stopped reading as a
/// time and started reading as a costume. Archivo's tabular figures still
/// hold their columns while a digit ticks, which is the only thing the mono
/// was actually needed for here.
TextStyle counter(double size, {double weight = 600}) => text(
      size,
      weight: weight,
      tracking: size * -0.035,
      height: 1,
    );

/// Titles run slightly narrow and tightly tracked so long track names survive
/// a phone-width row without ellipsing quite so early.
const double _titleWidth = 96;

TextTheme buildTextTheme(ColorScheme scheme) {
  final base = text(14);
  return TextTheme(
    displayLarge: text(52, weight: 600, tracking: -1.6, height: 1.02),
    displayMedium: text(42, weight: 600, tracking: -1.2, height: 1.04),
    displaySmall: text(34, weight: 600, tracking: -0.9, height: 1.06),
    headlineLarge: text(30, weight: 600, tracking: -0.7, height: 1.1),
    headlineMedium: text(26, weight: 600, tracking: -0.6, height: 1.12),
    headlineSmall: text(22, weight: 600, tracking: -0.4, height: 1.15),
    titleLarge:
        text(21, weight: 600, tracking: -0.3, height: 1.16, width: _titleWidth),
    titleMedium:
        text(16, weight: 600, tracking: -0.1, height: 1.25, width: _titleWidth),
    titleSmall: text(14, weight: 600, tracking: 0, height: 1.25),
    bodyLarge: base.copyWith(fontSize: 15, height: 1.38),
    bodyMedium: base.copyWith(height: 1.38),
    bodySmall: text(12.5, height: 1.3),
    labelLarge: text(13.5, weight: 600, tracking: 0.1),
    labelMedium: text(12, weight: 600, tracking: 0.3),
    labelSmall: panelLabel(),
  ).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
}
