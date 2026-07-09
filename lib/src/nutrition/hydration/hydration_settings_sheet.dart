import 'package:flutter/material.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:provider/provider.dart';

/// Hydration settings, in the app's standard editor sheet. Holds the daily goal
/// (0.25 L steps) for now — more settings land here later.
Future<void> showHydrationSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<NutritionState>.value(
      value: context.read<NutritionState>(),
      child: const _HydrationSettingsSheet(),
    ),
  );
}

class _HydrationSettingsSheet extends StatelessWidget {
  const _HydrationSettingsSheet();

  static const _step = 0.25;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionState>();
    final accent = Theme.of(context).colorScheme.primary;
    return EditorSheet(
      titleKey: 'nutrition.hydration.settings',
      valueText: '',
      accent: accent,
      children: [
        GlucoseStepperRow(
          labelKey: 'nutrition.hydration.goal_title',
          valueText: '${formatLitres(state.goalLitres)} L',
          accent: accent,
          onMinus: () => state.setGoalLitres(state.goalLitres - _step),
          onPlus: () => state.setGoalLitres(state.goalLitres + _step),
          valueChild: SportEditableNumber(
            valueText: '${formatLitres(state.goalLitres)} L',
            initial: state.goalLitres,
            min: 0.5,
            max: 10,
            decimal: true,
            onSubmit: state.setGoalLitres,
          ),
        ),
      ],
    );
  }
}
