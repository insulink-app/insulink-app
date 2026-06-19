import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_bolus_state.dart';
import 'package:provider/provider.dart';

/// Sliders for the two bolus-calculator factors (correction + carb ratio).
class ProfileBolusSelection extends StatelessWidget {
  const ProfileBolusSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileBolusState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FactorRow(
          labelKey: 'profile.bolus.correction',
          value: s.correctionFactor,
          min: ProfileBolusState.minCorrection,
          max: ProfileBolusState.maxCorrection,
          step: ProfileBolusState.correctionStep,
          valueLabel: Locales.string(
            context,
            'profile.bolus.correction.value',
            params: ['${s.correctionFactor}'],
          ),
          onChanged: s.setCorrectionFactor,
        ),
        const SizedBox(height: 20),
        _FactorRow(
          labelKey: 'profile.bolus.carb',
          value: s.carbFactor,
          min: ProfileBolusState.minCarb,
          max: ProfileBolusState.maxCarb,
          step: ProfileBolusState.carbStep,
          valueLabel: Locales.string(
            context,
            'profile.bolus.carb.value',
            params: ['${s.carbFactor}'],
          ),
          onChanged: s.setCarbFactor,
        ),
      ],
    );
  }
}

/// One labelled [Slider] over a single int factor. [valueLabel] is the
/// human-readable current value shown on the right.
class _FactorRow extends StatelessWidget {
  const _FactorRow({
    required this.labelKey,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.valueLabel,
    required this.onChanged,
  });

  final String labelKey;
  final int value, min, max, step;
  final String valueLabel;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divisions = (max - min) ~/ step;
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
              valueLabel,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
            ),
          ],
        ),
        Slider(
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          label: '$value',
          activeColor: theme.colorScheme.primary,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
