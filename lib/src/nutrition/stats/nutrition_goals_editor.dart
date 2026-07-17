import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:provider/provider.dart';

/// The three daily nutrition goals (carbs, protein, water) that feed the
/// progress bars on the nutrition tiles. Shared by the nutrition settings sheet
/// and the profile "Nutrition goals" topic page — both read/write the same
/// [NutritionState], which persists locally; the backend sync piggybacks on the
/// callers' existing push.
class NutritionGoalsEditor extends StatelessWidget {
  const NutritionGoalsEditor({super.key});

  static const _waterStep = 0.25;
  static const _carbsStep = 10.0;
  static const _proteinStep = 5.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionState>();
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _carbsRow(state, accent),
        const SizedBox(height: 16),
        _proteinRow(state, accent),
        const SizedBox(height: 16),
        _waterRow(state, accent),
      ],
    );
  }

  Widget _carbsRow(NutritionState state, Color accent) {
    return GlucoseStepperRow(
      labelKey: 'nutrition.carbs_goal',
      valueText: '${state.carbsGoalG} g',
      accent: accent,
      onMinus: () => state.setCarbsGoalG(state.carbsGoalG - _carbsStep),
      onPlus: () => state.setCarbsGoalG(state.carbsGoalG + _carbsStep),
      valueChild: SportEditableNumber(
        valueText: '${state.carbsGoalG} g',
        initial: state.carbsGoalG.toDouble(),
        min: 20,
        max: 800,
        onSubmit: state.setCarbsGoalG,
      ),
    );
  }

  Widget _proteinRow(NutritionState state, Color accent) {
    return GlucoseStepperRow(
      labelKey: 'nutrition.protein_goal',
      valueText: '${state.proteinGoalG} g',
      accent: accent,
      onMinus: () => state.setProteinGoalG(state.proteinGoalG - _proteinStep),
      onPlus: () => state.setProteinGoalG(state.proteinGoalG + _proteinStep),
      valueChild: SportEditableNumber(
        valueText: '${state.proteinGoalG} g',
        initial: state.proteinGoalG.toDouble(),
        min: 10,
        max: 400,
        onSubmit: state.setProteinGoalG,
      ),
    );
  }

  Widget _waterRow(NutritionState state, Color accent) {
    return GlucoseStepperRow(
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
    );
  }
}
