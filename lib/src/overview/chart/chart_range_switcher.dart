import 'package:flutter/material.dart';

/// Cross-fades a chart into its new window when the user picks another range
/// (24 h / 12 h / 6 h), with a slight zoom so it reads as the window changing.
///
/// Two static charts are blended, nothing inside a chart is animated: an
/// animation inside fl_chart re-lays-out the whole chart every frame
/// (`docs/PERFORMANCE.md`). Keyed by [generation], which only a pick on the
/// range selector moves, so a pinch or a pan updates in place.
class ChartRangeSwitcher extends StatelessWidget {
  const ChartRangeSwitcher({
    super.key,
    required this.generation,
    required this.child,
  });

  final int generation;
  final Widget child;

  static const Duration _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey<int>(generation), child: child),
    );
  }
}
