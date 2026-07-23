import 'package:flutter/material.dart';

import '../theme/status_colors.dart';

/// One horizontal sleep metric: a label + value, a filled progress bar, and the
/// configured target window drawn as a dashed box around the bar. The fill turns
/// green when [value] sits inside [targetMin]–[targetMax], amber otherwise. The
/// track scale stretches to fit both the value and the target so the dashed box
/// always lands somewhere readable.
class SleepStatBar extends StatelessWidget {
  const SleepStatBar({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.targetMin,
    required this.targetMax,
  });

  final String label;
  final String valueText;
  final int value;
  final int targetMin;
  final int targetMax;

  static const _height = 14.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onTarget = value >= targetMin && value <= targetMax;
    final scaleMax = [value, targetMax, 1].reduce((a, b) => a > b ? a : b) * 1.3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurface.withValues(alpha: 0.8))),
              Text(valueText,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: _height + 8,
                child: Stack(
                  children: [
                    Positioned(
                      top: 4,
                      left: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_height / 2),
                        child: LinearProgressIndicator(
                          value: (value / scaleMax).clamp(0.0, 1.0),
                          minHeight: _height,
                          backgroundColor:
                              scheme.onSurface.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(
                              onTarget ? context.positive : context.warning),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TargetBoxPainter(
                          startFraction: (targetMin / scaleMax).clamp(0.0, 1.0),
                          endFraction: (targetMax / scaleMax).clamp(0.0, 1.0),
                          color: scheme.onSurface.withValues(alpha: 0.55),
                          width: width,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Draws the dashed target rectangle around the bar's [startFraction]–
/// [endFraction] slice.
class _TargetBoxPainter extends CustomPainter {
  _TargetBoxPainter({
    required this.startFraction,
    required this.endFraction,
    required this.color,
    required this.width,
  });

  final double startFraction;
  final double endFraction;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final left = width * startFraction;
    final right = width * endFraction;
    final rect = Rect.fromLTRB(left, 0, right, size.height);
    final rrect =
        RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(6));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
            metric.extractPath(distance, distance + 4), paint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_TargetBoxPainter old) =>
      old.startFraction != startFraction ||
      old.endFraction != endFraction ||
      old.width != width ||
      old.color != color;
}
