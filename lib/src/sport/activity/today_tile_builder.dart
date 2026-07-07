import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_models.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/activity_estimate.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/weight/weight_detail_page.dart';

/// Icon for a Today box (shared by the grid and the layout editor).
IconData todayTileIcon(TodayTile tile) => switch (tile) {
  TodayTile.steps => Icons.directions_walk,
  TodayTile.distance => Icons.straighten,
  TodayTile.calories => Icons.local_fire_department,
  TodayTile.weight => Icons.monitor_weight,
  TodayTile.restingHr => Icons.favorite,
  TodayTile.sleep => Icons.bedtime,
  TodayTile.heartRate => Icons.monitor_heart,
  TodayTile.spo2 => Icons.air,
};

/// Localization key for a Today box label (shared by the grid and the editor).
String todayTileLabelKey(TodayTile tile) => switch (tile) {
  TodayTile.steps => 'sport.activity.steps',
  TodayTile.distance => 'sport.activity.distance',
  TodayTile.calories => 'sport.activity.calories',
  TodayTile.weight => 'sport.weight',
  TodayTile.restingHr => 'fitbit.resting_hr',
  TodayTile.sleep => 'fitbit.sleep',
  TodayTile.heartRate => 'fitbit.heart_rate',
  TodayTile.spo2 => 'fitbit.spo2',
};

/// Builds the [SportSummaryTile] for a Today box from the current sport + Fitbit
/// state: value, unit, and the tap target for the tiles that have a detail page.
class TodayTileBuilder {
  final SportActivityState activity;
  final SportState sport;
  final FitbitState fitbit;

  TodayTileBuilder(this.activity, this.sport, this.fitbit);

  double get _weightKg => sport.latestWeight?.kg ?? 70;

  double get _distanceKm =>
      activity.importedDistanceKm ??
      estimatedDistanceKm(activity.todaySteps, sport.strideCm);

  double get _calories =>
      activity.importedCalories ?? estimatedCalories(_distanceKm, _weightKg);

  SportSummaryTile build(BuildContext context, TodayTile tile) {
    final icon = todayTileIcon(tile);
    final label = todayTileLabelKey(tile);
    switch (tile) {
      case TodayTile.steps:
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: sportInt(activity.todaySteps),
          progress: activity.todaySteps / sport.stepsGoal,
          onTap: () => _detail(context, ActivityMetric.steps),
        );
      case TodayTile.distance:
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: sportDecimal(_distanceKm, 2),
          unit: 'km',
          progress: _distanceKm / sport.distanceGoalKm,
          onTap: () => _detail(context, ActivityMetric.distance),
        );
      case TodayTile.calories:
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: sportInt(_calories.round()),
          unit: 'kcal',
          progress: _calories / sport.caloriesGoal,
          onTap: () => _detail(context, ActivityMetric.calories),
        );
      case TodayTile.weight:
        final weight = sport.latestWeight;
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: weight == null ? '–' : sportDecimal(weight.kg, 1),
          unit: weight == null ? null : 'kg',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const WeightDetailPage()),
          ),
        );
      case TodayTile.restingHr:
        return _metric(icon, label, fitbit.todayRestingHr, 'bpm');
      case TodayTile.sleep:
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: formatSleepMinutes(fitbit.lastSleepMinutes),
        );
      case TodayTile.heartRate:
        return _metric(icon, label, fitbit.latestHr, 'bpm');
      case TodayTile.spo2:
        return _metric(icon, label, fitbit.latestSpo2, '%');
    }
  }

  SportSummaryTile _metric(IconData icon, String label, int? value, String unit) {
    return SportSummaryTile(
      icon: icon,
      labelKey: label,
      value: value == null ? '–' : sportInt(value),
      unit: value == null ? null : unit,
    );
  }

  void _detail(BuildContext context, ActivityMetric metric) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ActivityDetailPage(metric: metric)),
    );
  }
}
