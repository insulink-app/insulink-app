import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Where a live recording is now: an accent dot ringed in the page colour,
/// with an accent halo that keeps swelling outwards and fading, so the dot
/// reads as live and stays findable on the tinted map
/// (`docs/redesign/screens/30-training-live.png`). Fills its marker box; the
/// halo grows from the dot to the box edge.
class LivePositionDot extends StatefulWidget {
  const LivePositionDot({super.key});

  @override
  State<LivePositionDot> createState() => _LivePositionDotState();
}

class _LivePositionDotState extends State<LivePositionDot>
    with SingleTickerProviderStateMixin {
  static const _dotSize = 21.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _halo(colors, _controller.value),
        ),
        Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
            border: Border.all(color: colors.ground, width: 3),
          ),
        ),
      ],
    );
  }

  /// The halo at [progress] (0..1) of one beat: eased out from the dot's size
  /// to the full box while its opacity drops to zero.
  Widget _halo(InsulinkColors colors, double progress) {
    final eased = Curves.easeOut.transform(progress);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _dotSize + (constraints.maxWidth - _dotSize) * eased;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.35 * (1 - eased)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
