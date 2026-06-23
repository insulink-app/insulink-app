import 'package:flutter/material.dart';
import 'package:insulink/src/profile/bolus_factor_card.dart';
import 'package:insulink/src/profile/profile_bolus_state.dart';
import 'package:provider/provider.dart';

/// The two bolus-calculator factors (correction + carb ratio).
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
        BolusFactorCard(
          labelKey: 'profile.bolus.correction',
          valueKey: 'profile.bolus.correction.value',
          value: state.correctionFactor,
          min: ProfileBolusState.minCorrection,
          max: ProfileBolusState.maxCorrection,
          step: ProfileBolusState.correctionStep,
          onChanged: state.setCorrectionFactor,
        ),
        const SizedBox(height: 12),
        BolusFactorCard(
          labelKey: 'profile.bolus.carb',
          valueKey: 'profile.bolus.carb.value',
          value: state.carbFactor,
          min: ProfileBolusState.minCarb,
          max: ProfileBolusState.maxCarb,
          step: ProfileBolusState.carbStep,
          onChanged: state.setCarbFactor,
        ),
      ],
    );
  }
}
