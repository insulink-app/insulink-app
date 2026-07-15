import 'package:flutter/material.dart';
import 'package:insulink/src/base/setting_value_card.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:provider/provider.dart';

/// The bolus settings: the two calculator factors (correction + carb ratio),
/// the maximum bolus the injection sheet accepts, and how long insulin stays
/// active.
///
/// Like the glucose ranges, these are NOT inline sliders: a slider in the
/// scrolling settings list grabs vertical drags and shifts the value by
/// accident. Each factor is a tappable card that opens a focused bottom-sheet
/// editor (slider + steppers) where dragging is safe.
class ProfileBolusSelection extends StatelessWidget {
  const ProfileBolusSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileBolusState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingValueCard(
          labelKey: 'profile.bolus.correction',
          valueKey: 'profile.bolus.correction.value',
          value: state.correctionFactor,
          min: ProfileBolusState.minCorrection,
          max: ProfileBolusState.maxCorrection,
          step: ProfileBolusState.correctionStep,
          onChanged: state.setCorrectionFactor,
        ),
        const SizedBox(height: 12),
        SettingValueCard(
          labelKey: 'profile.bolus.carb',
          valueKey: 'profile.bolus.carb.value',
          value: state.carbFactor,
          min: ProfileBolusState.minCarb,
          max: ProfileBolusState.maxCarb,
          step: ProfileBolusState.carbStep,
          onChanged: state.setCarbFactor,
        ),
        const SizedBox(height: 12),
        SettingValueCard(
          labelKey: 'profile.bolus.max',
          valueKey: 'profile.bolus.max.value',
          value: state.maxBolus,
          min: ProfileBolusState.minMaxBolus,
          max: ProfileBolusState.maxMaxBolus,
          step: ProfileBolusState.maxBolusStep,
          onChanged: state.setMaxBolus,
        ),
        const SizedBox(height: 12),
        SettingValueCard(
          labelKey: 'profile.bolus.duration',
          valueKey: 'profile.bolus.duration.value',
          value: state.insulinDurationH,
          min: ProfileBolusState.minInsulinDuration,
          max: ProfileBolusState.maxInsulinDuration,
          step: ProfileBolusState.insulinDurationStep,
          onChanged: state.setInsulinDurationH,
        ),
      ],
    );
  }
}
