import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart' as type;
import '../../../shared/widgets/art_thumb.dart';
import '../../../shared/widgets/deck.dart';

/// A ranked row with its value drawn as a bar rather than left as a number to
/// compare by eye. Ten rows of "12 plays / 9 plays / 7 plays" is a table; the
/// bar is what makes it a chart.
class StatRankRow extends StatelessWidget {
  const StatRankRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.seed,
    required this.value,
    required this.maxValue,
    required this.primary,
    this.rank,
    this.artPath,
    this.secondary,
    this.onTap,
    this.onLongPress,
  });

  /// Position in the list, or null where the order is not a ranking (A–Z).
  final int? rank;
  final String title;
  final String subtitle;
  final String seed;
  final double value;
  final double maxValue;
  final String primary;
  final String? artPath;
  final String? secondary;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static const double _rankWidth = 22;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.deck;
    final fraction = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  if (rank != null)
                    SizedBox(
                      width: _rankWidth,
                      child: Text(
                        '$rank',
                        style: type
                            .instrument(12, weight: 500)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ArtThumb(
                    artPath: artPath,
                    size: 38,
                    borderRadius: 6,
                    seed: seed,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The figures are numbers and cannot be ellipsized, so at a
                  // large text scale they crowded the title out of the row and
                  // then ran past it. Cap them at a third of the row and let
                  // them shrink to fit that instead.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 3,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            primary,
                            style: type
                                .instrument(11, weight: 500)
                                .copyWith(color: scheme.onSurface),
                          ),
                          if (secondary != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              secondary!,
                              style: type
                                  .instrument(9.5)
                                  .copyWith(color: tokens.peak),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: rank != null ? _rankWidth : 0),
              child: SignalRule(
                value: fraction,
                height: 3,
                color: tokens.signalDim,
                radius: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
