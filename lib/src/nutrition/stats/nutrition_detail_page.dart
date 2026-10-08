import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/sport/daily_history/daily_history_view.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// History of a nutrition box (carbs, protein, bolus, water, meals) in the
/// shared daily-history layout. Carbs, protein and water are measured against
/// their goals from the nutrition settings; bolus and meals have none. Reached
/// by tapping a stat box.
class NutritionDetailPage extends StatelessWidget {
  const NutritionDetailPage({super.key, required this.tile});

  final NutritionTile tile;

  /// All days that have data, ascending, aggregated for this box.
  List<DailyValue> _series(MealState meals, NutritionState hydration) {
    final byDay = <DateTime, double>{};
    if (tile == NutritionTile.water) {
      for (final entry in hydration.entries) {
        final day = DateUtils.dateOnly(
          DateTime.fromMillisecondsSinceEpoch(entry.atEpochMs),
        );
        byDay[day] = (byDay[day] ?? 0) + entry.ml / 1000;
      }
    } else {
      for (final meal in meals.meals) {
        final day = DateUtils.dateOnly(meal.time);
        byDay[day] = (byDay[day] ?? 0) + _mealValue(meal);
      }
    }
    return [
      for (final entry in byDay.entries) (date: entry.key, value: entry.value),
    ]..sort((first, second) => first.date.compareTo(second.date));
  }

  double _mealValue(Meal meal) => switch (tile) {
    NutritionTile.carbs => meal.carbs,
    NutritionTile.protein => meal.protein,
    NutritionTile.bolus => meal.bolus,
    NutritionTile.meals => 1.0,
    NutritionTile.water => 0.0,
  };

  DailyMetric _metric(NutritionState goals) => DailyMetric(
    format: (value) => switch (tile) {
      NutritionTile.bolus => value.toStringAsFixed(1),
      NutritionTile.water => formatLitres(value),
      _ => value.toStringAsFixed(0),
    },
    unit: switch (tile) {
      NutritionTile.carbs || NutritionTile.protein => 'g',
      NutritionTile.bolus => 'E',
      NutritionTile.water => 'L',
      NutritionTile.meals => null,
    },
    goal: switch (tile) {
      NutritionTile.carbs => goals.carbsGoalG.toDouble(),
      NutritionTile.protein => goals.proteinGoalG.toDouble(),
      NutritionTile.water => goals.goalLitres,
      NutritionTile.bolus || NutritionTile.meals => null,
    },
  );

  @override
  Widget build(BuildContext context) {
    final hydration = context.watch<NutritionState>();
    final days = _series(context.watch<MealState>(), hydration);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(nutritionTileLabelKey(tile)),
      ),
      body: days.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsBold.chartLineUp,
              titleKey: 'nutrition.meals.empty',
              subtitleKey: 'nutrition.meals.empty_hint',
            )
          : DailyHistoryView(days: days, metric: _metric(hydration)),
    );
  }
}
