import 'package:flutter/material.dart';

/// One segment of an analysis selector strip (window, horizon, …).
///
/// Plain tappable rather than a ChoiceChip so no Material-3 selection overlay
/// flashes the accent colour on tap: selection is a grey fill only, and border
/// and size stay constant so the segment never resizes.
class AnalysisSegment extends StatelessWidget {
  const AnalysisSegment({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Plain tappable segment (not a ChoiceChip) so no Material-3 selection
    // overlay flashes the accent colour on tap. Selection is a grey fill only —
    // border and size stay constant so the segment never resizes.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? onSurface.withValues(alpha: 0.24)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
