import '../../injection/bolus_delivery.dart';
import '../../nutrition/meal/meal.dart';
import '../../nutrition/meal/meal_store.dart';
import '../../nutrition/nutrition_sync.dart';
import '../../pump/loop/loop_glucose.dart';
import '../../pump/split_bolus.dart';

/// Writes a given split-bolus part into the meal log, from the service isolate.
class SplitBolusPartLog {
  const SplitBolusPartLog();

  /// Logs the part as its own insulin-only entry, then pushes it so the next
  /// pull does not replace it away.
  ///
  /// Carries the glucose read for THIS part, not the one the meal was dosed
  /// at: the forecast model folds a logged dose's glucose into its glucose
  /// channel as a reading at that time, so a stale value would be a false
  /// one. With no usable reading it carries 0, which the model drops as a
  /// placeholder (the chart then sets that dot on its floor).
  Future<void> record(
    BolusDeliveryResult outcome,
    SplitBolusPlan plan,
    LoopGlucose glucose,
  ) async {
    const store = MealStore();
    final meals = await store.loadMeals();
    meals.add(
      Meal(
        time: DateTime.now(),
        carbs: 0,
        glucoseMgdl: glucose.isUsable ? glucose.mgdl : 0,
        bolus: outcome.recordedUnits,
        entries: const [],
        deliveredByPump: true,
        splitOf: plan.mealKey,
      ),
    );
    await store.saveMeals(meals);
    NutritionSync().pushMeals();
  }
}
