import 'package:flutter/widgets.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

import 'trash_entry.dart';

/// Hands a trashed entry back to the state it was deleted from, through that
/// state's own add path, so it is saved and synced like a new entry.
class TrashRestorer {
  const TrashRestorer(this.context);

  final BuildContext context;

  Future<void> restore(TrashEntry entry) {
    final data = entry.data;
    return switch (entry.kind) {
      TrashKind.meal => context.read<MealState>().addMeal(Meal.fromJson(data)),
      TrashKind.drink => context.read<NutritionState>().restoreEntry(
        DrinkEntry.fromJson(data),
      ),
      TrashKind.weight => context.read<SportState>().mergeWeights([
        WeightEntry.fromJson(data),
      ]),
      TrashKind.hba1c => _restoreHba1c(Hba1cEntry.fromJson(data)),
      TrashKind.cardio => context.read<CardioTrainingState>().addTraining(
        CardioTraining.fromJson(data),
      ),
      TrashKind.workout => context.read<TrainingState>().addSession(
        WorkoutSession.fromJson(data),
      ),
      TrashKind.routine => context.read<TrainingState>().restoreRoutine(
        SportRoutine.fromJson(data),
      ),
      TrashKind.exercise => context.read<TrainingState>().restoreExercise(
        SportExercise.fromJson(data),
      ),
      TrashKind.product => context.read<FoodState>().addProduct(
        FoodProduct.fromJson(data),
      ),
    };
  }

  Future<void> _restoreHba1c(Hba1cEntry entry) =>
      context.read<Hba1cState>().add(entry.percent, at: entry.time);
}
