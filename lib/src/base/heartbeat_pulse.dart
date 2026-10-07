import 'package:flutter/material.dart';

/// Scales its child with a continuous double-thump heartbeat (the classic
/// lub-dub), mimicking a pulse. Self-driving (repeats forever) — the parent shows
/// it only while a live heart rate is streaming.
class HeartbeatPulse extends StatefulWidget {
  const HeartbeatPulse({super.key, required this.child});

  final Widget child;

  @override
  State<HeartbeatPulse> createState() => _HeartbeatPulseState();
}

class _HeartbeatPulseState extends State<HeartbeatPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  // Two quick thumps early in the cycle, then rest — the classic lub-dub.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 52),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
