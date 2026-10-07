import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The night's sleep index (0–100) as a 96 px ring in the range colour, the
/// number large in its middle.
class SleepIndexRing extends StatelessWidget {
  const SleepIndexRing({super.key, required this.index});

  final int index;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Semantics(
      label: Locales.string(
        context,
        'google_health.sleep_page.index_semantics',
        params: ['$index'],
      ),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: _size,
        child: CustomPaint(
          painter: _RingPainter(
            share: index / 100,
            track: colors.line,
            arc: colors.range,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$index',
                style: InkText.bigValue.copyWith(color: colors.text),
              ),
              const SizedBox(height: 2),
              Text(
                Locales.string(context, 'google_health.sleep_page.index'),
                style: InkText.axis.copyWith(fontSize: 12, color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.share,
    required this.track,
    required this.arc,
  });

  final double share;
  final Color track;
  final Color arc;

  static const double _stroke = 7.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(_stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * share.clamp(0.0, 1.0),
      false,
      paint..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share || old.track != track || old.arc != arc;
}
