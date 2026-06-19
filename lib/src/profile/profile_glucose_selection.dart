import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_glucose_state.dart';
import 'package:provider/provider.dart';

/// Unit picker + target-range and alarm-threshold sliders. All values are kept
/// in mg/dL internally; labels are rendered in the chosen unit.
class ProfileGlucoseSelection extends StatelessWidget {
  const ProfileGlucoseSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileGlucoseState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'profile.unit',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _UnitButtons(state: s),
        const SizedBox(height: 24),
        _RangeRow(
          labelKey: 'profile.glucose.target',
          state: s,
          lowMgdl: s.targetLow,
          highMgdl: s.targetHigh,
          onChanged: (low, high) => s.setTargetRange(low, high),
        ),
        const SizedBox(height: 20),
        _RangeRow(
          labelKey: 'profile.glucose.alarms_low',
          state: s,
          lowMgdl: s.urgentLow,
          highMgdl: s.low,
          onChanged: (urgentLow, low) => s.setLowAlarms(urgentLow, low),
        ),
        const SizedBox(height: 20),
        _RangeRow(
          labelKey: 'profile.glucose.alarms_high',
          state: s,
          lowMgdl: s.high,
          highMgdl: s.urgentHigh,
          onChanged: (high, urgentHigh) => s.setHighAlarms(high, urgentHigh),
        ),
      ],
    );
  }
}

class _UnitButtons extends StatelessWidget {
  const _UnitButtons({required this.state});

  final ProfileGlucoseState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _unitButton(context, GlucoseUnit.mgdl, 'profile.unit.mgdl'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _unitButton(context, GlucoseUnit.mmol, 'profile.unit.mmol'),
        ),
      ],
    );
  }

  Widget _unitButton(BuildContext context, GlucoseUnit unit, String label) {
    final theme = Theme.of(context);
    final selected = state.unit == unit;
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6.0),
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(
              alpha: selected ? 0.2 : 0.4,
            ),
            width: selected ? 2 : 1,
          ),
        ),
      ),
      onPressed: () => state.setUnit(unit),
      child: LocaleText(
        label,
        style: TextStyle(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// One labelled [RangeSlider] over a low/high mg/dL pair. [onChanged] receives
/// the two thumb values (mg/dL, rounded to the configured step).
class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.labelKey,
    required this.state,
    required this.lowMgdl,
    required this.highMgdl,
    required this.onChanged,
  });

  final String labelKey;
  final ProfileGlucoseState state;
  final int lowMgdl;
  final int highMgdl;
  final void Function(int low, int high) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final min = ProfileGlucoseState.minMgdl.toDouble();
    final max = ProfileGlucoseState.maxMgdl.toDouble();
    const divisions =
        (ProfileGlucoseState.maxMgdl - ProfileGlucoseState.minMgdl) ~/
        ProfileGlucoseState.step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LocaleText(
              labelKey,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Text(
              '${state.format(lowMgdl)} – ${state.formatWithUnit(highMgdl)}',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
            ),
          ],
        ),
        RangeSlider(
          min: min,
          max: max,
          divisions: divisions,
          values: RangeValues(
            lowMgdl.toDouble().clamp(min, max),
            highMgdl.toDouble().clamp(min, max),
          ),
          labels: RangeLabels(state.format(lowMgdl), state.format(highMgdl)),
          activeColor: theme.colorScheme.primary,
          onChanged: (v) => onChanged(v.start.round(), v.end.round()),
        ),
      ],
    );
  }
}
