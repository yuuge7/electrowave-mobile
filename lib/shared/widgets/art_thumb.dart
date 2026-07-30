import 'dart:io';

import 'package:flutter/material.dart';

/// Album art thumbnail with a music-note placeholder fallback.
class ArtThumb extends StatelessWidget {
  const ArtThumb({
    super.key,
    required this.artPath,
    this.size = 48,
    this.borderRadius = 8,
    this.iconSize,
  });

  final String? artPath;
  final double size;
  final double borderRadius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (artPath != null && artPath!.isNotEmpty) {
      final mq = MediaQuery.of(context);
      // Always bound the decode: embedded art can be arbitrarily large, and
      // a full-resolution decode can fail (or exceed the GPU texture limit)
      // where a downscaled decode of the same file succeeds. When size is
      // infinite (full-screen art) the screen's shortest side is the most
      // it can ever be displayed at.
      final logicalSize = size.isFinite ? size : mq.size.shortestSide;
      child = Image.file(
        File(artPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (logicalSize * mq.devicePixelRatio).round(),
        errorBuilder: (_, _, _) => _placeholder(scheme),
      );
    } else {
      child = _placeholder(scheme);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: iconSize ?? size * 0.5,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
