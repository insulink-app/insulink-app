import 'package:flutter/widgets.dart';

/// One step of a two-finger gesture over a time chart: how far the fingers
/// spread ([scale] > 1 zooms in), how far their midpoint slid sideways in
/// pixels, the plot width it slid across, and where the midpoint sits across
/// the plot (0 = left edge, 1 = right edge).
typedef PinchStep = ({
  double scale,
  double focalTravelX,
  double plotWidth,
  double focalFraction,
});

/// Watches two-finger gestures over [child] and reports each move as a
/// [PinchStep], the same pinch-to-zoom and two-finger pan as the glucose
/// chart. A plain [Listener] observes pointers in parallel instead of claiming
/// them, so one-finger scrubbing in the chart keeps working.
class PinchZoomListener extends StatefulWidget {
  const PinchZoomListener({
    super.key,
    required this.onPinch,
    required this.child,
    this.axisInset = 0,
  });

  final ValueChanged<PinchStep> onPinch;
  final Widget child;

  /// Width of the axis labels left of the plot, not part of the time axis.
  final double axisInset;

  @override
  State<PinchZoomListener> createState() => _PinchZoomListenerState();
}

class _PinchZoomListenerState extends State<PinchZoomListener> {
  final Map<int, Offset> _pointers = {};
  double? _lastDistance;
  Offset? _lastFocal;

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _lastDistance = _distance();
      _lastFocal = _focal();
    }
  }

  /// Both previous values are read before they are replaced; overwriting the
  /// distance first would make every scale exactly 1.0.
  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers[event.pointer] = event.position;
    final previous = _lastDistance;
    final distance = _pointers.length == 2 ? _distance() : 0.0;
    if (previous == null || distance <= 0) {
      return;
    }
    final focal = _focal();
    final travel = focal.dx - (_lastFocal ?? focal).dx;
    _lastDistance = distance;
    _lastFocal = focal;
    widget.onPinch(_step(distance / previous, travel, focal));
  }

  PinchStep _step(double scale, double travel, Offset focal) {
    final box = context.findRenderObject() as RenderBox?;
    final plotWidth = (box?.size.width ?? 0) - widget.axisInset;
    final localX = (box?.globalToLocal(focal).dx ?? 0) - widget.axisInset;
    return (
      scale: scale,
      focalTravelX: travel,
      plotWidth: plotWidth,
      focalFraction: plotWidth <= 0 ? 1.0 : (localX / plotWidth).clamp(0, 1),
    );
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _lastDistance = null;
      _lastFocal = null;
    }
  }

  double _distance() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  Offset _focal() {
    final points = _pointers.values.toList();
    return (points[0] + points[1]) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
