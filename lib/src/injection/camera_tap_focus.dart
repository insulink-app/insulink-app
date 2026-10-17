import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Tap to focus on the live picture [child]: the tapped spot becomes the focus
/// and exposure point, and a white ring settles there for a moment so the user
/// sees where it took. A lens that cannot focus on a point keeps its own auto
/// focus; the ring then still answers the tap, harmlessly.
class CameraTapFocus extends StatefulWidget {
  const CameraTapFocus({super.key, required this.camera, required this.child});

  final CameraController camera;
  final Widget child;

  @override
  State<CameraTapFocus> createState() => _CameraTapFocusState();
}

class _CameraTapFocusState extends State<CameraTapFocus> {
  static const double _ringSize = 64;

  Offset? _ring;
  int _taps = 0;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// [local] within a picture of [size], handed to the camera as 0..1 of it,
  /// as the camera package expects. Not awaited: a newer tap supersedes it.
  void _focus(Offset local, Size size) {
    final point = Offset(
      (local.dx / size.width).clamp(0, 1),
      (local.dy / size.height).clamp(0, 1),
    );
    final camera = widget.camera;
    if (camera.value.focusPointSupported) {
      camera.setFocusPoint(point).ignore();
    }
    if (camera.value.exposurePointSupported) {
      camera.setExposurePoint(point).ignore();
    }
    _showRing(local);
  }

  void _showRing(Offset local) {
    _hide?.cancel();
    setState(() {
      _ring = local;
      _taps++;
    });
    _hide = Timer(const Duration(milliseconds: 1200), _hideRing);
  }

  void _hideRing() {
    if (mounted) {
      setState(() => _ring = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) =>
            _focus(details.localPosition, constraints.biggest),
        child: Stack(
          children: [widget.child, if (_ring case final ring?) _ringAt(ring)],
        ),
      ),
    );
  }

  /// The ring shrinks from 1.4× onto the spot, restarted by every tap.
  Widget _ringAt(Offset center) {
    return Positioned(
      left: center.dx - _ringSize / 2,
      top: center.dy - _ringSize / 2,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_taps),
          tween: Tween(begin: 1.4, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: _ringSize,
            height: _ringSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
