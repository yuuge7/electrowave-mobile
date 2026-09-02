import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The dominant hue of a piece of album art, so the player can take its
/// colour from the record that is playing.
///
/// Only the hue and saturation are kept. Lightness is decided at paint time
/// from the active theme, which is what stops a bright cover from washing out
/// the light theme or a murky one from disappearing into the dark one — and
/// it means one extraction serves both themes.
///
/// Written by hand rather than pulled from a palette package: the whole point
/// of this app is that it does not reach for the network, and a 32×32 decode
/// plus a histogram is smaller than the dependency would be.
@immutable
class ArtAccent {
  const ArtAccent({required this.hue, required this.saturation});

  final double hue;
  final double saturation;

  /// The accent as it should be painted on [scheme]'s surface.
  Color resolve(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return HSLColor.fromAHSL(
      1,
      hue,
      saturation.clamp(dark ? 0.35 : 0.40, dark ? 0.78 : 0.72),
      dark ? 0.56 : 0.34,
    ).toColor();
  }

  /// A heavily damped version for backdrops: the same hue, pulled most of the
  /// way to the surface so text over it keeps its contrast.
  Color backdrop(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final tinted = HSLColor.fromAHSL(
      1,
      hue,
      saturation.clamp(0.25, 0.7),
      dark ? 0.30 : 0.62,
    ).toColor();
    return Color.lerp(scheme.surface, tinted, dark ? 0.30 : 0.24)!;
  }
}

/// Decodes [path] small and picks the hue that carries the most saturated
/// colour. Returns null when the art is missing, unreadable, or essentially
/// greyscale — callers then keep the brand signal colour.
Future<ArtAccent?> extractArtAccent(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    // 32×32 is more than enough to find a dominant hue and costs almost
    // nothing; the full-size decode already happens elsewhere for display.
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;

    const bins = 36; // 10° per bin
    final weight = List<double>.filled(bins, 0);
    final saturationSum = List<double>.filled(bins, 0);

    final pixels = data.buffer.asUint8List();
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final a = pixels[i + 3];
      if (a < 128) continue;
      final color = Color.fromARGB(
        255,
        pixels[i],
        pixels[i + 1],
        pixels[i + 2],
      );
      final hsl = HSLColor.fromColor(color);
      // Skip what carries no hue information: near-greys, and anything so
      // dark or so blown out that its hue is noise.
      if (hsl.saturation < 0.18) continue;
      if (hsl.lightness < 0.12 || hsl.lightness > 0.92) continue;

      final bin = (hsl.hue / (360 / bins)).floor() % bins;
      // Weight by saturation so one vivid area outvotes a large dull one —
      // a cover's colour is the part that is actually coloured.
      final w = hsl.saturation * hsl.saturation;
      weight[bin] += w;
      saturationSum[bin] += hsl.saturation * w;
    }

    var best = -1;
    var bestWeight = 0.0;
    for (var i = 0; i < bins; i++) {
      if (weight[i] > bestWeight) {
        bestWeight = weight[i];
        best = i;
      }
    }
    // Nothing cleared the bar: a black-and-white sleeve, or a scan of paper.
    if (best < 0 || bestWeight <= 0) return null;

    return ArtAccent(
      hue: (best + 0.5) * (360 / bins),
      saturation: (saturationSum[best] / bestWeight).clamp(0.0, 1.0),
    );
  } catch (_) {
    // Unreadable art is not an error worth surfacing — it just means the
    // brand colour stays.
    return null;
  }
}
