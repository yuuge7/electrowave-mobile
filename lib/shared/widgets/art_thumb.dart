import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Album art thumbnail.
///
/// When there is no art, this does *not* fall back to one grey box with a
/// music note: a library of untagged files then renders as a wall of
/// identical tiles with nothing to tell them apart. The placeholder is a
/// gradient derived from [seed] plus its initials, so every album still looks
/// like itself.
class ArtThumb extends StatelessWidget {
  const ArtThumb({
    super.key,
    required this.artPath,
    this.size = 48,
    this.borderRadius = 8,
    this.iconSize,
    this.decodeWidth,
    this.seed,
  });

  final String? artPath;
  final double size;
  final double borderRadius;
  final double? iconSize;

  /// Logical width to decode at, for callers that size themselves from their
  /// parent's constraints (a grid tile) rather than a fixed [size].
  final double? decodeWidth;

  /// Text the art-less placeholder is generated from — an album or track
  /// name. The same string always produces the same colours and initials.
  final String? seed;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (artPath != null && artPath!.isNotEmpty) {
      final mq = MediaQuery.of(context);
      // Always bound the decode: embedded art can be arbitrarily large, and
      // a full-resolution decode can fail (or exceed the GPU texture limit)
      // where a downscaled decode of the same file succeeds. When size is
      // infinite (full-screen art) the screen's shortest side is the most
      // it can ever be displayed at.
      final logicalSize =
          decodeWidth ?? (size.isFinite ? size : mq.size.shortestSide);
      child = Image.file(
        File(artPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (logicalSize * mq.devicePixelRatio).round(),
        errorBuilder: (_, _, _) => _Placeholder(
          seed: seed,
          iconSize: iconSize,
          size: size,
          decodeWidth: decodeWidth,
        ),
      );
    } else {
      child = _Placeholder(
        seed: seed,
        iconSize: iconSize,
        size: size,
        decodeWidth: decodeWidth,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// The generated tile on its own, for things that never have artwork but
/// still need to look like themselves: playlists, smart lists, folders.
/// Sharing one generator is what keeps a playlist row and an art-less album
/// visibly part of the same system.
class GeneratedTile extends StatelessWidget {
  const GeneratedTile({
    super.key,
    required this.seed,
    this.size = 48,
    this.radius = 8,
    this.icon,
  });

  final String seed;
  final double size;
  final double radius;

  /// Drawn instead of initials — for a kind of thing rather than a named one.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (top, bottom) = _gradientFor(seed, dark: dark);
    final label = ((top.computeLuminance() + bottom.computeLuminance()) / 2) >
            0.42
        ? Colors.black.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.88);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.44, color: label)
          : Center(
              child: Text(
                _initials(seed),
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: label,
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.seed,
    required this.iconSize,
    required this.size,
    required this.decodeWidth,
  });

  final String? seed;
  final double? iconSize;
  final double size;
  final double? decodeWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = seed?.trim() ?? '';

    if (key.isEmpty) {
      // `size` is infinity for full-bleed art, and `infinity * 0.5` is not a
      // drawable icon size — that is why the album grid used to render an
      // empty box rather than the fallback note.
      final resolved = iconSize ??
          (size.isFinite
              ? size * 0.5
              : (decodeWidth != null ? decodeWidth! * 0.4 : 48));
      return Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.music_note,
          size: resolved,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final (top, bottom) = _gradientFor(key, dark: dark);
    // Pick the label colour from the gradient's own luminance rather than the
    // theme's, since these colours are generated and can land either side.
    final label = ((top.computeLuminance() + bottom.computeLuminance()) / 2) >
            0.42
        ? Colors.black.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.88);

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 48,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 48,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
          ),
          child: Center(
            child: Text(
              _initials(key),
              maxLines: 1,
              // Fixed against the text scale: this is a graphic, and letting
              // it scale overflows a 48 dp thumbnail at large font sizes.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: label,
                fontSize: box * 0.34,
                fontWeight: FontWeight.w600,
                letterSpacing: box * 0.01,
                height: 1,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Two related hues from a stable hash of [key], kept mid-saturation so they
/// read as artwork rather than as UI chrome, and biased light or dark to sit
/// inside the current theme.
(Color, Color) _gradientFor(String key, {required bool dark}) {
  var hash = 0;
  for (final unit in key.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  // A second hue a short way round the wheel: enough for a visible gradient,
  // not enough to look like two unrelated colours.
  final hue2 = (hue + 24 + (hash >> 9) % 26) % 360;

  final saturation = dark ? 0.42 : 0.52;
  final topLight = dark ? 0.32 : 0.68;
  final bottomLight = dark ? 0.17 : 0.52;

  return (
    HSLColor.fromAHSL(1, hue, saturation, topLight).toColor(),
    HSLColor.fromAHSL(1, hue2, saturation, bottomLight).toColor(),
  );
}

/// First letters of the first two words: "Field Recordings Vol. 2" -> "FR".
String _initials(String key) {
  final words = key
      .split(RegExp(r'[\s\-_/]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final first = _firstLetter(words.first);
  if (words.length == 1) return first.toUpperCase();
  final second = _firstLetter(words[1]);
  return (first + second).toUpperCase();
}

String _firstLetter(String word) {
  for (final rune in word.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[A-Za-z0-9À-ɏ]').hasMatch(ch)) return ch;
  }
  return word[0];
}
