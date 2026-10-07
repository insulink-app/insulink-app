import 'package:flutter/material.dart';

/// The first screen's entrance: it fades in and rises a little while the
/// splash fades out above it, so the launch reads as one movement instead of a
/// cut from a loader to a finished page. Plays once per app start, and not at
/// all with reduced motion.
class LaunchReveal extends StatefulWidget {
  const LaunchReveal({super.key, required this.child});

  final Widget child;

  static const Duration duration = Duration(milliseconds: 600);

  /// How far the page rises, as a share of its height (about 17 px on a phone).
  static const double rise = 0.02;

  @override
  State<LaunchReveal> createState() => _LaunchRevealState();
}

class _LaunchRevealState extends State<LaunchReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: LaunchReveal.duration,
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, LaunchReveal.rise),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
