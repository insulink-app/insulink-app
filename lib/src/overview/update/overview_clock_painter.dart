import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws the small "next reading" clock: a background track ring, a progress
/// arc filling toward the next reading, and two continuously spinning hands.
class ClockRingPainter extends CustomPainter {
  ClockRingPainter({
    required this.progress,
    required this.spin,
    required this.color,
    required this.track,
  });

  /// 0..1 ring fill toward the next reading.
  final double progress;

  /// 0..1 rotation phase for the (continuously spinning) hands.
  final double spin;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    _drawRing(canvas, center, radius);
    _drawHands(canvas, center, radius);
  }

  /// Background track ring + progress arc (12 o'clock start, clockwise).
  void _drawRing(Canvas canvas, Offset center, double radius) {
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = track;
    canvas.drawCircle(center, radius - 1.5, trackPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 1.5),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      arcPaint,
    );
  }

  /// Clock hands: minute hand spins once per cycle, hour hand 1/6 as fast.
  void _drawHands(Canvas canvas, Offset center, double radius) {
    final hand = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final minuteAngle = spin * 2 * math.pi - math.pi / 2;
    final hourAngle = (spin / 6) * 2 * math.pi - math.pi / 2;
    canvas.drawLine(
      center,
      center +
          Offset(math.cos(minuteAngle), math.sin(minuteAngle)) *
              (radius * 0.52),
      hand,
    );
    canvas.drawLine(
      center,
      center +
          Offset(math.cos(hourAngle), math.sin(hourAngle)) * (radius * 0.30),
      hand,
    );
    canvas.drawCircle(center, 1.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(ClockRingPainter old) =>
      old.progress != progress ||
      old.spin != spin ||
      old.color != color ||
      old.track != track;
}
