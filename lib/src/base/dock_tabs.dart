import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/dock_tab_slot.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

/// The tabs inside the dock's capsule, with one pill that glides between them.
///
/// The pill's position is a continuous tab index driven by a spring, so a tab
/// change animates instead of jumping. A horizontal drag across the capsule
/// moves the pill with the finger and lands on the nearest tab on release, the
/// way the floating tab bars on recent phones do. Each slot widens as the pill
/// arrives, which is what makes room for the active tab's label.
class DockTabs extends StatefulWidget {
  const DockTabs({
    super.key,
    required this.pageBodies,
    required this.selectedIndex,
    required this.badges,
    required this.onSelect,
  });

  final List<AppPageBody> pageBodies;
  final int selectedIndex;
  final Map<int, int> badges;
  final ValueChanged<int> onSelect;

  @override
  State<DockTabs> createState() => _DockTabsState();
}

class _DockTabsState extends State<DockTabs>
    with SingleTickerProviderStateMixin {
  /// How much wider the active slot is than an idle one (in idle slot widths).
  static const double _grow = 1.8;

  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.82,
  );

  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );

  bool _dragging = false;

  int get _lastIndex => widget.pageBodies.length - 1;

  @override
  void didUpdateWidget(DockTabs old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex && !_dragging) {
      _settle(widget.selectedIndex, velocity: 0);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  /// Springs the pill to [index], carrying over the finger's [velocity].
  void _settle(int index, {required double velocity}) {
    _position.animateWith(
      SpringSimulation(_spring, _position.value, index.toDouble(), velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _startDrag(),
          onHorizontalDragUpdate: (details) => _drag(details, width),
          onHorizontalDragEnd: (details) => _endDrag(details, width),
          child: AnimatedBuilder(
            animation: _position,
            builder: (context, _) => _layout(context, width),
          ),
        );
      },
    );
  }

  void _startDrag() {
    _dragging = true;
    _position.stop();
  }

  /// Moves the pill with the finger, one idle slot width per tab, and ticks
  /// once for every tab it crosses.
  void _drag(DragUpdateDetails details, double width) {
    final before = _position.value.round();
    final step = width / widget.pageBodies.length;
    _position.value = (_position.value + details.delta.dx / step).clamp(
      0.0,
      _lastIndex.toDouble(),
    );
    if (_position.value.round() != before) {
      HapticFeedback.selectionClick();
    }
  }

  /// Lands on the nearest tab, nudged by a flick, and opens it.
  void _endDrag(DragEndDetails details, double width) {
    _dragging = false;
    final step = width / widget.pageBodies.length;
    final velocity = details.velocity.pixelsPerSecond.dx / step;
    final projected = _position.value + velocity * 0.12;
    final target = projected.round().clamp(0, _lastIndex);
    _settle(target, velocity: velocity);
    if (target != widget.selectedIndex) {
      widget.onSelect(target);
    }
  }

  /// How close the pill is to slot [index]: 1 on it, 0 a full slot away.
  double _closeness(int index) =>
      (1 - (_position.value - index).abs()).clamp(0.0, 1.0);

  Widget _layout(BuildContext context, double width) {
    final weights = [
      for (var index = 0; index <= _lastIndex; index++)
        1 + _grow * _closeness(index),
    ];
    final unit = width / weights.reduce((sum, weight) => sum + weight);
    final lefts = <double>[0];
    for (final weight in weights) {
      lefts.add(lefts.last + weight * unit);
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        _pill(context, lefts, weights, unit),
        Row(
          children: [
            for (var index = 0; index <= _lastIndex; index++)
              SizedBox(
                width: weights[index] * unit,
                child: _slot(context, index),
              ),
          ],
        ),
      ],
    );
  }

  /// The pill spans the slot under the position, blended toward the next one
  /// while it travels.
  Widget _pill(
    BuildContext context,
    List<double> lefts,
    List<double> weights,
    double unit,
  ) {
    final from = _position.value.floor().clamp(0, _lastIndex);
    final to = _position.value.ceil().clamp(0, _lastIndex);
    final travel = _position.value - from;
    double lerp(double start, double end) => start + (end - start) * travel;
    return Positioned(
      left: lerp(lefts[from], lefts[to]),
      width: lerp(weights[from] * unit, weights[to] * unit),
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.insulinkColors.accentSoft,
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  Widget _slot(BuildContext context, int index) {
    return DockTabSlot(
      body: widget.pageBodies[index],
      closeness: _closeness(index),
      selected: index == widget.selectedIndex,
      badge: widget.badges[index],
      onTap: () => widget.onSelect(index),
    );
  }
}
