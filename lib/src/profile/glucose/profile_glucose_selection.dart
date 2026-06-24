import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/glucose_range_card.dart';
import 'package:insulink/src/profile/glucose/glucose_unit_selector.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Unit picker + target-range and alarm-threshold editors. All values are kept
/// in mg/dL internally; labels are rendered in the chosen unit.
///
/// The ranges are NOT inline sliders anymore: a slider embedded in the scrolling
/// settings list grabs vertical drags and shifts a thumb by accident. Each range
/// is a tappable card that opens a focused bottom-sheet editor (slider + steppers)
/// where dragging is safe because nothing scrolls behind it.
class ProfileGlucoseSelection extends StatelessWidget {
  const ProfileGlucoseSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileGlucoseState>();
    final glucoseColors = Theme.of(context).extension<GlucoseColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'profile.unit',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        GlucoseUnitSelector(state: state),
        const SizedBox(height: 24),
        GlucoseRangeCard(
          state: state,
          accent: glucoseColors.inRange,
          labelKey: 'profile.glucose.target',
          lowLabelKey: 'profile.glucose.target_low',
          highLabelKey: 'profile.glucose.target_high',
          low: state.targetLow,
          high: state.targetHigh,
          onChanged: state.setTargetRange,
        ),
        const SizedBox(height: 12),
        GlucoseRangeCard(
          state: state,
          accent: glucoseColors.low,
          labelKey: 'profile.glucose.alarms_low',
          lowLabelKey: 'profile.glucose.urgent_low',
          highLabelKey: 'profile.glucose.low',
          low: state.urgentLow,
          high: state.low,
          onChanged: state.setLowAlarms,
          onTest: () => context.read<G7Controller>().testAlarm(high: false),
        ),
        const SizedBox(height: 12),
        GlucoseRangeCard(
          state: state,
          accent: glucoseColors.high,
          labelKey: 'profile.glucose.alarms_high',
          lowLabelKey: 'profile.glucose.high',
          highLabelKey: 'profile.glucose.urgent_high',
          low: state.high,
          high: state.urgentHigh,
          onChanged: state.setHighAlarms,
          onTest: () => context.read<G7Controller>().testAlarm(high: true),
        ),
      ],
    );
  }
}
