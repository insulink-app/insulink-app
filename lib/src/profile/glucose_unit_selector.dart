import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';

/// iOS-style segmented control for the glucose display unit.
class GlucoseUnitSelector extends StatelessWidget {
  const GlucoseUnitSelector({super.key, required this.state});

  final ProfileGlucoseState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(theme, GlucoseUnit.mgdl, 'profile.unit.mgdl'),
          ),
          Expanded(
            child: _segment(theme, GlucoseUnit.mmol, 'profile.unit.mmol'),
          ),
        ],
      ),
    );
  }

  Widget _segment(ThemeData theme, GlucoseUnit unit, String labelKey) {
    final selected = state.unit == unit;
    return GestureDetector(
      onTap: () => state.setUnit(unit),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.onSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: LocaleText(
          labelKey,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected
                ? theme.colorScheme.surface
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
