import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final hours in options) _chip(theme, hours),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, int hours) {
    final isSelected = selected == hours;
    return GestureDetector(
      onTap: () => onChanged(hours),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${hours}h',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
