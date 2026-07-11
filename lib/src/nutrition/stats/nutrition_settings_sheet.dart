import 'package:flutter/material.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_button.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:provider/provider.dart';

/// Unified nutrition settings: the daily carb / protein / water goals plus the
/// box-layout editor. Replaces the old hydration-only sheet — reached from the
/// single settings button in the stats header.
Future<void> showNutritionSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<NutritionState>.value(
      value: context.read<NutritionState>(),
      child: const _NutritionSettingsSheet(),
    ),
  );
  // Sync the (possibly changed) goals to the backend once editing is done.
  if (context.mounted) {
    await ProfileSettings().push(context);
  }
}

class _NutritionSettingsSheet extends StatelessWidget {
  const _NutritionSettingsSheet();

  static const _waterStep = 0.25;
  static const _carbsStep = 10.0;
  static const _proteinStep = 5.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionState>();
    final accent = Theme.of(context).colorScheme.primary;
    return EditorSheet(
      titleKey: 'nutrition.settings',
      valueText: '',
      accent: accent,
      children: [
        GlucoseStepperRow(
          labelKey: 'nutrition.carbs_goal',
          valueText: '${state.carbsGoalG} g',
          accent: accent,
          onMinus: () =>
              state.setCarbsGoalG(state.carbsGoalG - _carbsStep),
          onPlus: () => state.setCarbsGoalG(state.carbsGoalG + _carbsStep),
          valueChild: SportEditableNumber(
            valueText: '${state.carbsGoalG} g',
            initial: state.carbsGoalG.toDouble(),
            min: 20,
            max: 800,
            onSubmit: state.setCarbsGoalG,
          ),
        ),
        const SizedBox(height: 16),
        GlucoseStepperRow(
          labelKey: 'nutrition.protein_goal',
          valueText: '${state.proteinGoalG} g',
          accent: accent,
          onMinus: () =>
              state.setProteinGoalG(state.proteinGoalG - _proteinStep),
          onPlus: () =>
              state.setProteinGoalG(state.proteinGoalG + _proteinStep),
          valueChild: SportEditableNumber(
            valueText: '${state.proteinGoalG} g',
            initial: state.proteinGoalG.toDouble(),
            min: 10,
            max: 400,
            onSubmit: state.setProteinGoalG,
          ),
        ),
        const SizedBox(height: 16),
        GlucoseStepperRow(
          labelKey: 'nutrition.hydration.goal_title',
          valueText: '${formatLitres(state.goalLitres)} L',
          accent: accent,
          onMinus: () => state.setGoalLitres(state.goalLitres - _waterStep),
          onPlus: () => state.setGoalLitres(state.goalLitres + _waterStep),
          valueChild: SportEditableNumber(
            valueText: '${formatLitres(state.goalLitres)} L',
            initial: state.goalLitres,
            min: 0.5,
            max: 10,
            decimal: true,
            onSubmit: state.setGoalLitres,
          ),
        ),
        const SizedBox(height: 24),
        const NutritionLayoutButton(),
      ],
    );
  }
}
