import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// GitHub-contributions-style grid: one column per week, one cell per day,
/// shaded by how much was listened that day.
class ListeningHeatmap extends StatelessWidget {
  const ListeningHeatmap({
    super.key,
    required this.year,
    required this.byDay,
    this.cellSize = 12,
    this.gap = 3,
    this.onDayTap,
  });

  final int year;

  /// Local midnight → listened milliseconds.
  final Map<DateTime, int> byDay;
  final double cellSize;

  /// Spacing between cells; shrunk on the share card, where the whole year has
  /// to fit the card width without scrolling.
  final double gap;
  final ValueChanged<DateTime>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = DateTime(year);
    final end = DateTime(year + 1);

    // Columns start on Monday, so the first one is padded out to wherever
    // 1 January fell.
    final leadingBlanks = start.weekday - DateTime.monday;
    final dayCount = end.difference(start).inDays;
    final columns = ((leadingBlanks + dayCount) / 7).ceil();

    // Shading is relative to the busiest day of the year: an hour a day looks
    // the same on a heavy year as on a light one, which is what makes the
    // shape readable rather than the absolute numbers.
    final peak = byDay.values.fold<int>(0, (a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Below roughly 8dp per column the labels run into each other, and
          // the shrunk grid on the share card is exactly that case.
          if (cellSize + gap >= 8) ...[
            _MonthLabels(
              year: year,
              columns: columns,
              leadingBlanks: leadingBlanks,
              cellSize: cellSize,
              gap: gap,
            ),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++)
                Padding(
                  padding: EdgeInsets.only(right: gap),
                  child: Column(
                    children: [
                      for (var row = 0; row < 7; row++)
                        Padding(
                          padding: EdgeInsets.only(bottom: gap),
                          child: _cell(
                            context,
                            scheme,
                            start,
                            column * 7 + row - leadingBlanks,
                            dayCount,
                            peak,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _Legend(cellSize: cellSize, scheme: scheme),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    ColorScheme scheme,
    DateTime start,
    int dayIndex,
    int dayCount,
    int peak,
  ) {
    // Padding cells before 1 January and after 31 December.
    if (dayIndex < 0 || dayIndex >= dayCount) {
      return SizedBox(width: cellSize, height: cellSize);
    }

    final day = DateTime(start.year, start.month, start.day + dayIndex);
    final ms = byDay[day] ?? 0;
    final color = ms == 0
        ? scheme.surfaceContainerHighest
        : Color.lerp(
            scheme.primary.withValues(alpha: 0.25),
            scheme.primary,
            peak == 0 ? 0 : (ms / peak).clamp(0.0, 1.0),
          )!;

    return Tooltip(
      message:
          '${DateFormat.yMMMd().format(day)}\n'
          '${Duration(milliseconds: ms).inMinutes} min',
      child: GestureDetector(
        onTap: onDayTap == null ? null : () => onDayTap!(day),
        child: Container(
          width: cellSize,
          height: cellSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _MonthLabels extends StatelessWidget {
  const _MonthLabels({
    required this.year,
    required this.columns,
    required this.leadingBlanks,
    required this.cellSize,
    required this.gap,
  });

  final int year;
  final int columns;
  final int leadingBlanks;
  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final columnWidth = cellSize + gap;

    // A month's label sits over the column holding its first day.
    final labels = <int, String>{};
    for (var month = 1; month <= 12; month++) {
      final first = DateTime(year, month);
      final dayIndex = first.difference(DateTime(year)).inDays;
      labels[(dayIndex + leadingBlanks) ~/ 7] = DateFormat.MMM().format(first);
    }

    return SizedBox(
      height: 14,
      width: columns * columnWidth,
      child: Stack(
        children: [
          for (final entry in labels.entries)
            Positioned(
              left: entry.key * columnWidth,
              child: Text(entry.value, style: style),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.cellSize, required this.scheme});

  final double cellSize;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final steps = [
      scheme.surfaceContainerHighest,
      for (final t in const [0.25, 0.5, 0.75, 1.0])
        Color.lerp(scheme.primary.withValues(alpha: 0.25), scheme.primary, t)!,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Less', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 6),
        for (final color in steps)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: cellSize,
              height: cellSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 3),
        Text('More', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
