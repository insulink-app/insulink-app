import 'package:flutter/material.dart';

/// Animates a tab change along the horizontal axis, the way Material's shared
/// axis transition does: the old page drifts toward the side it is leaving to
/// and is gone in the first third, then the new one drifts in from the side of
/// the new tab. The two are never visible at once, so the layouts of two pages
/// never show through each other mid-change.
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

  /// How far a page drifts, in logical pixels.
  static const double _drift = 30;

  /// The share of the change in which the old page fades out; the new page
  /// fades in over the rest.
  static const double _handover = 0.35;

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
      duration: const Duration(milliseconds: 300),
      transitionBuilder: _transition,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(widget.index), child: widget.child),
    );
  }

  /// Whether a page is leaving is read from its animation every frame, not
  /// decided when the transition is built: [AnimatedSwitcher] keeps the
  /// transition a page got while it was arriving and only runs it backwards
  /// once the page leaves, so a choice baked in at build time sends the old
  /// page out the way it came, fading over most of the change.
  Widget _transition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, page) {
        final leaving =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        final shown = (leaving ? _fadeOut : _fadeIn).transform(animation.value);
        final side = (leaving ? -_drift : _drift) * _direction;
        return Opacity(
          opacity: shown,
          child: Transform.translate(
            offset: Offset(side * (1 - shown), 0),
            child: page,
          ),
        );
      },
    );
  }

  /// A leaving page runs from 1 back to 0, so it is gone once its value drops
  /// below `1 - _handover`, i.e. in the first [_handover] of the change.
  static const Curve _fadeOut = Interval(
    1 - _handover,
    1,
    curve: Curves.easeInCubic,
  );

  /// The arriving page waits out the handover, then eases in.
  static const Curve _fadeIn = Interval(
    _handover,
    1,
    curve: Curves.easeOutCubic,
  );
}
