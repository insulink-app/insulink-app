import 'package:flutter/material.dart';
import 'package:insulink/src/base/segmented_toggle.dart';

/// Segmented control to pick a visible time window in hours (e.g. 24 / 12 / 6),
/// shared by the glucose overview chart and the heart-rate page so both read the
/// same. Stateless — the parent owns the [selected] value and persistence.
class HourRangeSelector extends StatelessWidget {
  const HourRangeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.options = const [24, 12, 6],
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final List<int> options;

  @override
  Widget build(BuildContext context) {
    return SegmentedToggle<int>.page(
      selected: selected,
      onChanged: onChanged,
      options: [for (final hours in options) (value: hours, label: '$hours h')],
    );
  }
}
