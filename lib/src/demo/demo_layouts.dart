import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';

/// The boxes the demo shows on the overview, the Sport "Today" grid and the
/// nutrition stats: the same selection and order as the screenshots on the
/// website, instead of the app's sparser first-launch defaults.
class DemoLayouts {
  static const _storage = FlutterSecureStorage();

  Future<void> arrange() async {
    await _write(OverviewLayoutState.key, _overviewOrder, _overviewShown);
    await _write(TodayLayoutState.key, _todayOrder, _todayShown);
    await _write(NutritionLayoutState.key, _nutritionOrder, _nutritionShown);
  }

  Future<void> _write<T extends Enum>(
    String key,
    List<T> order,
    Set<T> shown,
  ) => _storage.write(
    key: key,
    value: TileLayoutState.encode(order, {
      for (final tile in order)
        if (!shown.contains(tile)) tile,
    }),
  );

  static const _overviewOrder = [
    OverviewBox.distance,
    OverviewBox.calories,
    OverviewBox.steps,
    OverviewBox.weight,
    OverviewBox.restingHr,
    OverviewBox.heartRate,
    OverviewBox.sleep,
    OverviewBox.bolus,
    OverviewBox.water,
    OverviewBox.respiratoryRate,
    OverviewBox.carbs,
    OverviewBox.protein,
    OverviewBox.meals,
    OverviewBox.hba1c,
  ];

  static const _overviewShown = {
    OverviewBox.steps,
    OverviewBox.weight,
    OverviewBox.heartRate,
    OverviewBox.sleep,
    OverviewBox.bolus,
    OverviewBox.water,
  };

  static const _todayOrder = [
    TodayTile.steps,
    TodayTile.distance,
    TodayTile.calories,
    TodayTile.weight,
    TodayTile.restingHr,
    TodayTile.respiratoryRate,
    TodayTile.sleep,
    TodayTile.heartRate,
    TodayTile.hba1c,
  ];

  static const _todayShown = {
    TodayTile.steps,
    TodayTile.distance,
    TodayTile.calories,
    TodayTile.weight,
    TodayTile.restingHr,
    TodayTile.respiratoryRate,
  };

  static const _nutritionOrder = [
    NutritionTile.carbs,
    NutritionTile.protein,
    NutritionTile.meals,
    NutritionTile.bolus,
    NutritionTile.water,
  ];

  static const _nutritionShown = {
    NutritionTile.carbs,
    NutritionTile.protein,
    NutritionTile.meals,
    NutritionTile.bolus,
  };
}
