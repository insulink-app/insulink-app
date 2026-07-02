import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Body metrics used by the sport features: stride length (for the step-based
/// distance estimate) and body height (for the BMI on the weight page). Same
/// stepper rows as the activity sheet, reachable from the profile settings too.
class ProfileBodySelection extends StatelessWidget {
  const ProfileBodySelection({super.key});

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlucoseStepperRow(
          labelKey: 'sport.activity.stride',
          valueText: '${sport.strideCm} cm',
          accent: scheme.primary,
          onMinus: () => _bumpStride(context, -5),
          onPlus: () => _bumpStride(context, 5),
          valueChild: SportEditableNumber(
            valueText: '${sport.strideCm} cm',
            initial: sport.strideCm.toDouble(),
            min: 40,
            max: 120,
            onSubmit: (value) =>
                context.read<SportState>().setStrideCm(value.round()),
          ),
        ),
        const SizedBox(height: 20),
        GlucoseStepperRow(
          labelKey: 'sport.activity.height',
          valueText: '${sport.heightCm} cm',
          accent: scheme.primary,
          onMinus: () => _bumpHeight(context, -1),
          onPlus: () => _bumpHeight(context, 1),
          valueChild: SportEditableNumber(
            valueText: '${sport.heightCm} cm',
            initial: sport.heightCm.toDouble(),
            min: 100,
            max: 250,
            onSubmit: (value) =>
                context.read<SportState>().setHeightCm(value.round()),
          ),
        ),
        const SizedBox(height: 16),
        LocaleText(
          'profile.body.note',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  void _bumpStride(BuildContext context, int delta) {
    HapticFeedback.selectionClick();
    final sport = context.read<SportState>();
    sport.setStrideCm(sport.strideCm + delta);
  }

  void _bumpHeight(BuildContext context, int delta) {
    HapticFeedback.selectionClick();
    final sport = context.read<SportState>();
    sport.setHeightCm(sport.heightCm + delta);
  }
}
