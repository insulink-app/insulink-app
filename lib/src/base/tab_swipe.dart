import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Switches the shell's tabs with a horizontal flick across the page, like
/// dragging the dock's pill: a flick to the left opens the tab to the right.
///
/// Only a flick counts, not the distance: a slow sideways drift while scrolling
/// switches nothing. Anything inside the page that drags sideways itself (the
/// analysis tabs, a chart's scrubber) sits deeper and wins the gesture first, so
/// it keeps working as before.
class TabSwipe extends StatelessWidget {
  const TabSwipe({
    super.key,
    required this.index,
    required this.count,
    required this.onSelect,
    required this.child,
  });

  /// Logical pixels per second a flick needs before it switches the tab.
  static const double _minimumFlick = 400;

  final int index;
  final int count;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _flicked,
      child: child,
    );
  }

  /// Opens the neighbour the flick points to, when there is one.
  void _flicked(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _minimumFlick) {
      return;
    }
    final target = index + (velocity < 0 ? 1 : -1);
    if (target < 0 || target >= count) {
      return;
    }
    HapticFeedback.selectionClick();
    onSelect(target);
  }
}
