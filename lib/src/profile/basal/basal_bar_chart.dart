import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';

/// A 24-bar chart of a basal profile. When [onChanged] is non-null it is
/// interactive: dragging over a bar paints that hour's rate from the touch
/// height, and the touched hour becomes [selectedHour] via [onSelect]. Passing
/// null [onChanged] renders a read-only preview (the settings summary card).
class BasalBarChart extends StatelessWidget {
  const BasalBarChart({
    super.key,
    required this.rates,
    this.selectedHour,
    this.onChanged,
    this.onSelect,
    this.height = 160,
  });

  final List<double> rates;
  final int? selectedHour;
  final void Function(int hour, double rate)? onChanged;
  final void Function(int hour)? onSelect;
  final double height;

  /// Height reserved under the bars for the hour labels (matches `_bar`).
  static const _labelHeight = 12.0;

  bool get _interactive => onChanged != null;

  int _hourAt(Offset local, double width) =>
      ((local.dx / width) * 24).floor().clamp(0, 23);

  /// Tapping only selects the hour (so its value isn't nudged by accident);
  /// use the steppers or drag to change it.
  void _select(Offset local, double width) {
    onSelect?.call(_hourAt(local, width));
    HapticFeedback.selectionClick();
  }

  /// Dragging paints the rate of the touched hour from the touch height.
  void _paint(Offset local, double width) {
    final hour = _hourAt(local, width);
    onSelect?.call(hour);
    final fraction = (1 - local.dy / (height - _labelHeight)).clamp(0.0, 1.0);
    onChanged?.call(hour, fraction * BasalProfile.maxRate);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final scale = rates.fold(0.5, (m, r) => r > m ? r : m);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapDown:
              _interactive ? (d) => _select(d.localPosition, width) : null,
          onPanStart:
              _interactive ? (d) => _paint(d.localPosition, width) : null,
          onPanUpdate:
              _interactive ? (d) => _paint(d.localPosition, width) : null,
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var hour = 0; hour < 24; hour++)
                  _bar(context, hour, scale),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, int hour, double scale) {
    final scheme = Theme.of(context).colorScheme;
    final selected = hour == selectedHour;
    final color =
        selected ? scheme.primary : scheme.primary.withValues(alpha: 0.45);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.75),
        child: Column(
          children: [
            Expanded(
              child: FractionallySizedBox(
                alignment: Alignment.bottomCenter,
                heightFactor: (rates[hour] / scale).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 12,
              child: hour % 6 == 0
                  ? Text(
                      '$hour',
                      style: TextStyle(
                        fontSize: 9,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
