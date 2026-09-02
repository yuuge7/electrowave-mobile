import 'dart:io';

import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared loading / empty / error surfaces.
///
/// Every screen used to inline its own `Center(child: Text('Error: $error'))`,
/// which put a raw exception — including absolute file paths — in front of the
/// user, and a bare centred spinner that made the layout jump when data landed.
/// These three widgets are the one place that behaviour is decided.

// ---------------------------------------------------------------------------
// Empty
// ---------------------------------------------------------------------------

/// A surface with nothing in it *and a reason why*, plus the action that would
/// change that. Prefer this over a bare centred string.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.secondaryAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Widget? secondaryAction;

  /// Tighter spacing for empty states inside a sheet or a short column.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compact ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(compact ? 16 : 20),
              ),
              child: Icon(
                icon,
                size: compact ? 28 : 36,
                color: scheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? 12 : 20),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 16 : 24),
              action!,
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: 8),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

/// Turns an exception into a sentence a person can act on. The raw object is
/// kept behind a collapsed "Technical details" so a bug report is still
/// possible, but it never lands on screen unasked — several of these carry
/// absolute paths from the user's storage.
String describeError(Object error) {
  if (error is PathNotFoundException) {
    return 'A file or folder this needs is no longer where it was. '
        'Re-scanning your library usually fixes it.';
  }
  if (error is FileSystemException) {
    return "Couldn't read from storage. Check that Electrowave still has "
        'music and audio access.';
  }
  if (error is DriftWrappedException) {
    return "The library database couldn't be read. If this keeps happening, "
        'restore a backup from Settings.';
  }
  return 'Something went wrong loading this.';
}

class ErrorStateView extends StatefulWidget {
  const ErrorStateView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  State<ErrorStateView> createState() => _ErrorStateViewState();
}

class _ErrorStateViewState extends State<ErrorStateView> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: widget.compact ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 36,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              describeError(widget.error),
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (widget.onRetry != null)
                  FilledButton.tonalIcon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Try again'),
                  ),
                TextButton(
                  onPressed: () => setState(() => _showDetails = !_showDetails),
                  child: Text(
                    _showDetails ? 'Hide details' : 'Technical details',
                  ),
                ),
              ],
            ),
            if (_showDetails) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  widget.error.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/// Placeholder rows sized like the real ones, so the layout doesn't jump when
/// data lands. Honours the platform's reduce-motion setting.
class ListSkeleton extends StatefulWidget {
  const ListSkeleton({
    super.key,
    this.rowCount = 8,
    this.rowHeight = 64,
    this.leadingSize = 48,
    this.leadingRadius = 8,
  });

  final int rowCount;
  final double rowHeight;
  final double leadingSize;
  final double leadingRadius;

  @override
  State<ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<ListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pulsing placeholder is decoration, not information — drop it entirely
    // when the platform asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ExcludeSemantics(
      child: Semantics(
        label: 'Loading',
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final color = base.withValues(alpha: 0.4 + _pulse.value * 0.35);
            return ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.rowCount,
              itemExtent: widget.rowHeight,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _Block(
                      width: widget.leadingSize,
                      height: widget.leadingSize,
                      radius: widget.leadingRadius,
                      color: color,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Block(
                            // Vary the widths so it reads as text, not as a
                            // stack of identical bars.
                            width: 120.0 + (index % 4) * 45,
                            height: 13,
                            radius: 4,
                            color: color,
                          ),
                          const SizedBox(height: 8),
                          _Block(
                            width: 80.0 + (index % 3) * 35,
                            height: 11,
                            radius: 4,
                            color: color,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _Block(width: 34, height: 11, radius: 4, color: color),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Grid counterpart of [ListSkeleton], for the albums tab.
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.tileCount = 8});

  final int tileCount;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    return ExcludeSemantics(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: tileCount,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Block(
                width: double.infinity,
                height: double.infinity,
                radius: 12,
                color: color,
              ),
            ),
            const SizedBox(height: 10),
            _Block(width: 110, height: 12, radius: 4, color: color),
            const SizedBox(height: 6),
            _Block(width: 70, height: 10, radius: 4, color: color),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AsyncValue wrapper
// ---------------------------------------------------------------------------

enum SkeletonKind { list, grid, spinner }

/// `AsyncValue.when` with the project's loading and error surfaces already
/// filled in, so screens only have to describe their data case.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.skeleton = SkeletonKind.list,
    this.onRetry,
    this.skeletonRowHeight = 64,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final SkeletonKind skeleton;
  final double skeletonRowHeight;

  /// What "Try again" should do. Omit for streams that recover on their own.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => switch (skeleton) {
        SkeletonKind.list => ListSkeleton(rowHeight: skeletonRowHeight),
        SkeletonKind.grid => const GridSkeleton(),
        SkeletonKind.spinner => const Center(
          child: CircularProgressIndicator(),
        ),
      },
      error: (error, _) => ErrorStateView(error: error, onRetry: onRetry),
    );
  }
}
