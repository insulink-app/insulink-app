import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/fitbit_heart_rate_monitor.dart';
import 'package:insulink/src/google_health/google_health_detail_page.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/heart_rate_page.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/activity_estimate.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/weight/weight_detail_page.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Icon for a Today box (shared by the grid and the layout editor).
///
/// Bold weight, unlike the rest of the app: a summary box carries its glyph
/// bare, with no badge behind it, so the thin Regular stroke washes out against
/// the box's tint. The heavier stroke gives it presence without a louder colour.
/// The live heart stays Fill — it beats, and a solid shape reads at a glance.
IconData todayTileIcon(TodayTile tile) => switch (tile) {
  TodayTile.steps => PhosphorIconsBold.personSimpleWalk,
  TodayTile.distance => PhosphorIconsBold.ruler,
  TodayTile.calories => PhosphorIconsBold.fire,
  TodayTile.weight => PhosphorIconsBold.scales,
  TodayTile.restingHr => PhosphorIconsBold.heartbeat,
  TodayTile.sleep => PhosphorIconsBold.moon,
  TodayTile.heartRate => PhosphorIconsFill.heart,
  TodayTile.spo2 => PhosphorIconsBold.drop,
  TodayTile.respiratoryRate => PhosphorIconsBold.wind,
};

/// Localization key for a Today box label (shared by the grid and the editor).
String todayTileLabelKey(TodayTile tile) => switch (tile) {
  TodayTile.steps => 'sport.activity.steps',
  TodayTile.distance => 'sport.activity.distance',
  TodayTile.calories => 'sport.activity.calories',
  TodayTile.weight => 'sport.weight',
  TodayTile.restingHr => 'google_health.resting_hr',
  TodayTile.sleep => 'google_health.sleep',
  TodayTile.heartRate => 'google_health.heart_rate',
  TodayTile.spo2 => 'google_health.spo2',
  TodayTile.respiratoryRate => 'google_health.respiratory_rate',
};

/// Builds the [SportSummaryTile] for a Today box from the current sport + Google Health
/// state: value, unit, and the tap target for the tiles that have a detail page.
class TodayTileBuilder {
  final SportActivityState activity;
  final SportState sport;
  final GoogleHealthState health;

  TodayTileBuilder(this.activity, this.sport, this.health);

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
        return _metric(
          context,
          icon,
          label,
          health.todayRestingHr,
          'bpm',
          GoogleHealthMetric.restingHr,
        );
      case TodayTile.sleep:
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: formatSleepMinutes(health.lastSleepMinutes),
          onTap: () => _googleHealthDetail(context, GoogleHealthMetric.sleep),
        );
      case TodayTile.heartRate:
        final live = health.liveHrMonitor.status == FitbitHrStatus.streaming;
        final bpm = live ? health.liveHrMonitor.bpm : health.latestHr;
        return SportSummaryTile(
          icon: icon,
          labelKey: label,
          value: bpm == null ? '–' : sportInt(bpm),
          unit: bpm == null ? null : 'bpm',
          pulse: live,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HeartRatePage()),
          ),
        );
      case TodayTile.spo2:
        return _metric(
          context,
          icon,
          label,
          health.latestSpo2,
          '%',
          GoogleHealthMetric.spo2,
        );
      case TodayTile.respiratoryRate:
        return _metric(
          context,
          icon,
          label,
          health.latestRespiratoryRate,
          'rpm',
          GoogleHealthMetric.respiratoryRate,
        );
    }
  }

  SportSummaryTile _metric(
    BuildContext context,
    IconData icon,
    String label,
    int? value,
    String unit,
    GoogleHealthMetric metric,
  ) {
    return SportSummaryTile(
      icon: icon,
      labelKey: label,
      value: value == null ? '–' : sportInt(value),
      unit: value == null ? null : unit,
      onTap: () => _googleHealthDetail(context, metric),
    );
  }

  void _detail(BuildContext context, ActivityMetric metric) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityDetailPage(metric: metric),
      ),
    );
  }

  void _googleHealthDetail(BuildContext context, GoogleHealthMetric metric) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoogleHealthDetailPage(metric: metric),
      ),
    );
  }
}
