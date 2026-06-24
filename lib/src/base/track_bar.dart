import 'package:flutter/material.dart';

/// A horizontal track with a coloured band between [startFraction] and
/// [endFraction] (both 0..1). The shared primitive behind the glucose range bar
/// and the bolus fill bar.
class TrackBar extends StatelessWidget {
  const TrackBar({
    super.key,
    required this.startFraction,
    required this.endFraction,
    required this.color,
    this.height = 8,
  });

  final double startFraction, endFraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _stack(context, constraints.maxWidth),
      ),
    );
  }

  Widget _stack(BuildContext context, double width) {
    final left = startFraction.clamp(0.0, 1.0) * width;
    final right = endFraction.clamp(0.0, 1.0) * width;
    return Stack(
      children: [
        Positioned.fill(child: _track(context)),
        Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: (right - left).clamp(4.0, width),
          child: _band(),
        ),
      ],
    );
  }

  Widget _track(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }

  Widget _band() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
