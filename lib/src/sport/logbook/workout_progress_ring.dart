import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A circular progress ring with a [child] at its centre — the workout summary's
/// headline. [fraction] (0..1) fills the arc clockwise from 12 o'clock in
/// [color] over a faint [track]; the centre carries the big value.
class WorkoutProgressRing extends StatelessWidget {
  const WorkoutProgressRing({
    super.key,
    required this.fraction,
    required this.color,
    required this.child,
    this.size = 148,
  });

  final double fraction;
  final Color color;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withValues(
      alpha: 0.08,
    );
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: fraction.clamp(0, 1),
          color: color,
          track: track,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      fraction * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
