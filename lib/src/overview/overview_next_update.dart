import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compact "next reading" indicator: an animated clock whose ring fills as the
/// next ~5-minute G7 reading approaches, with a short m:ss countdown. Replaces
/// the verbose last/next-update text — the absolute last-reception time now
/// lives on the sensor page.
class OverviewNextUpdate extends StatefulWidget {
  const OverviewNextUpdate({super.key, required this.lastUpdate});

  final DateTime? lastUpdate;

  @override
  State<OverviewNextUpdate> createState() => _OverviewNextUpdateState();
}

class _OverviewNextUpdateState extends State<OverviewNextUpdate>
    with SingleTickerProviderStateMixin {
  /// G7 EGV cadence — a new value roughly every 5 minutes.
  static const _intervalSec = 300;

  /// Drives the rotating clock hands so the indicator always looks "alive";
  /// also serves as the once-per-frame tick that refreshes the countdown.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  static String _mmss(Duration d) {
    final s = d.inSeconds.abs();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        final last = widget.lastUpdate;

        double progress;
        Color color;
        String value;

        if (last == null) {
          progress = 0;
          color = Colors.grey;
          value = '—';
        } else {
          final elapsed = DateTime.now().difference(last);
          final remaining = const Duration(seconds: _intervalSec) - elapsed;
          progress = (elapsed.inSeconds / _intervalSec).clamp(0.0, 1.0);
          if (remaining.isNegative) {
            // Past the expected slot — the reading is late (skipped/poor signal).
            color = Colors.orangeAccent;
            value = '+${_mmss(remaining)}';
          } else {
            color = scheme.onSurface.withValues(alpha: 0.5);
            value = _mmss(remaining);
          }
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CustomPaint(
                painter: _ClockPainter(
                  progress: progress,
                  spin: _spin.value,
                  color: color,
                  track: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
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
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Background track ring + progress arc (12 o'clock start, clockwise).
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = track;
    canvas.drawCircle(c, r - 1.5, trackPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1.5),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      arcPaint,
    );

    // Clock hands: minute hand spins once per cycle, hour hand 1/6 as fast.
    final hand = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final minA = spin * 2 * math.pi - math.pi / 2;
    final hourA = (spin / 6) * 2 * math.pi - math.pi / 2;
    canvas.drawLine(
      c,
      c + Offset(math.cos(minA), math.sin(minA)) * (r * 0.52),
      hand,
    );
    canvas.drawLine(
      c,
      c + Offset(math.cos(hourA), math.sin(hourA)) * (r * 0.30),
      hand,
    );
    canvas.drawCircle(c, 1.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.progress != progress ||
      old.spin != spin ||
      old.color != color ||
      old.track != track;
}
