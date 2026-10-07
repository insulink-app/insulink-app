import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The coverage strip itself: one slice per bucket, and a way to point at one.
///
/// **Not a [Tooltip].** A tooltip only opens on a long press on a touchscreen,
/// and a slice here is about seven pixels wide, so the gesture that would reveal
/// what a gap was is one nobody can land. A tap anywhere along the strip picks
/// the slice under the finger instead, dragging sweeps through them, and a mouse
/// does the same on hover, which is the desktop half of the same question.
class ConnectionTimelineStrip extends StatelessWidget {
  const ConnectionTimelineStrip({
    super.key,
    required this.covered,
    required this.selected,
    required this.onSelect,
  });

  /// One flag per bucket, oldest first.
  final List<bool> covered;

  /// The slice being described right now, or null.
  final int? selected;

  /// Reports the slice under a touch or pointer; null when the pointer leaves.
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          onHover: (event) => _pick(event.localPosition.dx, constraints),
          onExit: (_) => onSelect(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _pick(details.localPosition.dx, constraints),
            onHorizontalDragUpdate: (details) =>
                _pick(details.localPosition.dx, constraints),
            child: _slices(context),
          ),
        ),
      ),
    );
  }

  /// Which slice a pointer at [dx] is over. The one-pixel gaps between slices
  /// are ignored: a touch that lands in a gap belongs to a slice either way, and
  /// the arithmetic without them is the arithmetic that can't be off by one.
  void _pick(double dx, BoxConstraints constraints) {
    if (covered.isEmpty || constraints.maxWidth <= 0) {
      return;
    }
    final index = (dx / constraints.maxWidth * covered.length).floor().clamp(
      0,
      covered.length - 1,
    );
    if (index != selected) {
      onSelect(index);
    }
  }

  Widget _slices(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < covered.length; index++) ...[
          if (index > 0) const SizedBox(width: 1),
          Expanded(child: _slice(context, scheme, index)),
        ],
      ],
    );
  }

  Widget _slice(BuildContext context, ColorScheme scheme, int index) {
    final isSelected = index == selected;
    return Container(
      decoration: BoxDecoration(
        color: covered[index]
            ? scheme.primary
            : context.ink.line,
        borderRadius: BorderRadius.circular(2),
        border: isSelected
            ? Border.all(color: scheme.onSurface, width: 1.5)
            : null,
      ),
    );
  }
}
