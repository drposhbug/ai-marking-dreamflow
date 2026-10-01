import 'dart:math';

import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/theme.dart';

class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final String label;

  /// White ring and label for a dark card (the dashboard's board-green
  /// header). On a light card that white all but vanished, so pass false
  /// there for a green ring and dark label.
  final bool onDark;

  const ProgressRing({super.key, required this.value, required this.size, required this.stroke, required this.label, this.onDark = true});

  @override
  Widget build(BuildContext context) {
    final ring = onDark ? Colors.white.withValues(alpha: 0.92) : AiMarkerColors.secondary;
    final track = onDark ? Colors.white.withValues(alpha: 0.20) : AiMarkerColors.secondary.withValues(alpha: 0.16);
    final text = onDark ? Colors.white : AiMarkerColors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _RingPainter(value: value, color: ring, bg: track, stroke: stroke)),
          Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: text, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color bg;
  final double stroke;

  _RingPainter({required this.value, required this.color, required this.bg, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = min(size.width, size.height) / 2 - stroke / 2;

    final bgPaint = Paint()..color = bg..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round;
    final fgPaint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi, false, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi * value.clamp(0, 1), false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.value != value || oldDelegate.color != color || oldDelegate.bg != bg || oldDelegate.stroke != stroke;
}
