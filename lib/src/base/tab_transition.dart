import 'package:flutter/material.dart';

/// Animates a tab change: the new page fades in while sliding a little in
/// from the side of the tab it came from, the old one fades out the other way.
///
/// Keyed by [index], so only a real tab change animates; rebuilds of the same
/// tab pass straight through.
class TabTransition extends StatefulWidget {
  const TabTransition({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<TabTransition> {
  /// Which way the last change went: 1 toward a tab further right, -1 left.
  double _direction = 1;

  /// How far a page slides, as a share of its width.
  static const double _shift = 0.06;

  @override
  void didUpdateWidget(TabTransition old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _direction = widget.index > old.index ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: _transition,
      child: KeyedSubtree(key: ValueKey(widget.index), child: widget.child),
    );
  }

  /// The outgoing page's animation runs backwards, so its offset starts on the
  /// opposite side and it leaves toward where the new page came from.
  Widget _transition(Widget child, Animation<double> animation) {
    final incoming = child.key == ValueKey(widget.index);
    final side = (incoming ? _shift : -_shift) * _direction;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: Offset(side, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
