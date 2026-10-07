import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The 3-2-1 before a training starts, over the map: each number turns and
/// springs in while the one before it grows and fades out, inside an accent
/// ring that sweeps once per second. With reduced motion the numbers only
/// cross-fade and the ring stays still.
class TrainingCountdown extends StatefulWidget {
  const TrainingCountdown({super.key, required this.count});

  final int count;

  @override
  State<TrainingCountdown> createState() => _TrainingCountdownState();
}

class _TrainingCountdownState extends State<TrainingCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _second = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..forward();

  /// Every new number restarts the ring's sweep.
  @override
  void didUpdateWidget(TrainingCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _second.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final still = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: colors.ground.withValues(alpha: 0.55),
      child: Center(
        child: SizedBox.square(
          dimension: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _second,
                builder: (context, _) => CustomPaint(
                  painter: _RingPainter(
                    progress: still ? 1 : _second.value,
                    track: colors.line,
                    sweep: colors.accent,
                  ),
                ),
              ),
              Center(child: _number(colors, still)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _number(InsulinkColors colors, bool still) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: still ? 150 : 550),
      switchInCurve: still ? Curves.linear : Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          _transition(child, animation, still),
      child: Text(
        '${widget.count}',
        key: ValueKey(widget.count),
        style: InkText.bigValue.copyWith(fontSize: 120, color: colors.text),
      ),
    );
  }

  /// The incoming number turns a quarter and scales up from small, springing
  /// a little past full size; the outgoing one (its animation runs backwards)
  /// grows as it fades. The spring overshoots 1, so the opacity is clamped.
  Widget _transition(Widget child, Animation<double> animation, bool still) {
    if (still) {
      return FadeTransition(opacity: animation, child: child);
    }
    final incoming = child.key == ValueKey(widget.count);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, number) {
        final value = animation.value;
        final scale = incoming ? 0.3 + 0.7 * value : 1.6 - 0.6 * value;
        final turn = incoming ? (1 - value) * -math.pi / 2 : 0.0;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: turn,
            child: Transform.scale(scale: scale, child: number),
          ),
        );
      },
    );
  }
}

/// A full track with an accent arc from twelve o'clock over [progress].
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.sweep,
  });

  final double progress;
  final Color track;
  final Color sweep;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(ring, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      ring,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint..color = sweep,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.sweep != sweep;
}
