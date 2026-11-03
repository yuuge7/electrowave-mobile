import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  WaveformPainter(this.samples, this.fraction, this.color);
  final List<double> samples;
  final double fraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final count = (size.width / 4).floor().clamp(1, samples.length);
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final sample = samples[(i * samples.length / count).floor()];
      final height = sample.clamp(0.02, 1.0) * size.height;
      paint.color = color.withValues(alpha: i / count <= fraction ? 0.9 : 0.25);
      final x = (i + 0.5) * size.width / count;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.samples != samples || old.fraction != fraction || old.color != color;
}
