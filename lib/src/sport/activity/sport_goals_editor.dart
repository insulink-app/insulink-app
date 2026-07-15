import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// The three daily-goal steppers (steps, distance, calories) that feed the
/// progress bars on the activity tiles. Shared by the activity bottom sheet and
/// the profile "Goals" topic page — both read/write the same [SportState], which
/// persists locally; the backend sync piggybacks on the callers' existing push.
class SportGoalsEditor extends StatelessWidget {
  const SportGoalsEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepsRow(sport, accent),
        const SizedBox(height: 16),
        _distanceRow(sport, accent),
        const SizedBox(height: 16),
        _caloriesRow(sport, accent),
        const SizedBox(height: 16),
        _weightRow(sport, accent),
        const SizedBox(height: 12),
        LocaleText(
          'sport.goals.note',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _stepsRow(SportState sport, Color accent) {
    return GlucoseStepperRow(
      labelKey: 'sport.goals.steps',
      valueText: sportInt(sport.stepsGoal),
      accent: accent,
      onMinus: () => _bumpSteps(sport, -500),
      onPlus: () => _bumpSteps(sport, 500),
      valueChild: SportEditableNumber(
        valueText: sportInt(sport.stepsGoal),
        initial: sport.stepsGoal.toDouble(),
        min: 1000,
        max: 50000,
        onSubmit: (value) => sport.setStepsGoal(value.round()),
      ),
    );
  }

  Widget _distanceRow(SportState sport, Color accent) {
    final valueText = '${sportDecimal(sport.distanceGoalKm, 1)} km';
    return GlucoseStepperRow(
      labelKey: 'sport.goals.distance',
      valueText: valueText,
      accent: accent,
      onMinus: () => _bumpDistance(sport, -500),
      onPlus: () => _bumpDistance(sport, 500),
      valueChild: SportEditableNumber(
        valueText: valueText,
        initial: sport.distanceGoalKm,
        min: 0.5,
        max: 50,
        decimal: true,
        onSubmit: (km) => sport.setDistanceGoalM((km * 1000).round()),
      ),
    );
  }

  Widget _caloriesRow(SportState sport, Color accent) {
    return GlucoseStepperRow(
      labelKey: 'sport.goals.calories',
      valueText: '${sportInt(sport.caloriesGoal)} kcal',
      accent: accent,
      onMinus: () => _bumpCalories(sport, -50),
      onPlus: () => _bumpCalories(sport, 50),
      valueChild: SportEditableNumber(
        valueText: '${sportInt(sport.caloriesGoal)} kcal',
        initial: sport.caloriesGoal.toDouble(),
        min: 50,
        max: 5000,
        onSubmit: (value) => sport.setCaloriesGoal(value.round()),
      ),
    );
  }

  Widget _weightRow(SportState sport, Color accent) {
    final valueText = '${sportDecimal(sport.weightGoalKg, 1)} kg';
    return GlucoseStepperRow(
      labelKey: 'sport.goals.weight',
      valueText: valueText,
      accent: accent,
      onMinus: () => _bumpWeight(sport, -0.5),
      onPlus: () => _bumpWeight(sport, 0.5),
      valueChild: SportEditableNumber(
        valueText: valueText,
        initial: sport.weightGoalKg,
        min: 30,
        max: 250,
        decimal: true,
        onSubmit: (kg) => sport.setWeightGoalKg(kg),
      ),
    );
  }

  void _bumpWeight(SportState sport, double delta) {
    HapticFeedback.selectionClick();
    sport.setWeightGoalKg(sport.weightGoalKg + delta);
  }

  void _bumpSteps(SportState sport, int delta) {
    HapticFeedback.selectionClick();
    sport.setStepsGoal(sport.stepsGoal + delta);
  }

  void _bumpDistance(SportState sport, int deltaM) {
    HapticFeedback.selectionClick();
    sport.setDistanceGoalM((sport.distanceGoalKm * 1000).round() + deltaM);
  }

  void _bumpCalories(SportState sport, int delta) {
    HapticFeedback.selectionClick();
    sport.setCaloriesGoal(sport.caloriesGoal + delta);
  }
}
