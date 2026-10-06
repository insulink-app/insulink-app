import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_detail_page.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/heart_rate_page.dart';
import 'package:insulink/src/hba1c/hba1c_page.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/activity_estimate.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/base/stat_tile.dart';
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
IconData todayTileIcon(TodayTile tile) => switch (tile) {
  TodayTile.steps => PhosphorIconsBold.personSimpleWalk,
  TodayTile.distance => PhosphorIconsBold.ruler,
  TodayTile.calories => PhosphorIconsBold.fire,
  TodayTile.weight => PhosphorIconsBold.scales,
  TodayTile.restingHr => PhosphorIconsBold.heartbeat,
  TodayTile.sleep => PhosphorIconsBold.moon,
  TodayTile.heartRate => PhosphorIconsBold.heart,
  TodayTile.respiratoryRate => PhosphorIconsBold.wind,
  TodayTile.hba1c => PhosphorIconsBold.testTube,
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
  TodayTile.respiratoryRate => 'google_health.respiratory_rate',
  TodayTile.hba1c => 'hba1c._',
};

/// Builds the [StatTile] for a Today box from the current sport + Google Health
/// state: value, unit, and the tap target for the tiles that have a detail page.
class TodayTileBuilder {
  final SportActivityState activity;
  final SportState sport;
  final GoogleHealthState health;
  final Hba1cState hba1c;

  TodayTileBuilder(this.activity, this.sport, this.health, this.hba1c);

  double get _weightKg => sport.latestWeight?.kg ?? 70;

  double get _distanceKm =>
      activity.importedDistanceKm ??
      estimatedDistanceKm(activity.todaySteps, sport.strideCm);

  double get _calories =>
      activity.importedCalories ?? estimatedCalories(_distanceKm, _weightKg);

  StatTile build(BuildContext context, TodayTile tile) {
    final icon = todayTileIcon(tile);
    final label = todayTileLabelKey(tile);
    if (tile.isGoogleHealth && !health.connected) {
      return StatTile(
        icon: icon,
        labelKey: label,
        value: '–',
        unavailable: true,
      );
    }
    switch (tile) {
      case TodayTile.steps:
        return StatTile(
          icon: icon,
          labelKey: label,
          value: sportInt(activity.todaySteps),
          progress: activity.todaySteps / sport.stepsGoal,
          onTap: () => _detail(context, ActivityMetric.steps),
        );
      case TodayTile.distance:
        return StatTile(
          icon: icon,
          labelKey: label,
          value: sportDecimal(_distanceKm, 2),
          unit: 'km',
          progress: _distanceKm / sport.distanceGoalKm,
          onTap: () => _detail(context, ActivityMetric.distance),
        );
      case TodayTile.calories:
        return StatTile(
          icon: icon,
          labelKey: label,
          value: sportInt(_calories.round()),
          unit: 'kcal',
          progress: _calories / sport.caloriesGoal,
          onTap: () => _detail(context, ActivityMetric.calories),
        );
      case TodayTile.weight:
        final weight = sport.latestWeight;
        return StatTile(
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
        return StatTile(
          icon: icon,
          labelKey: label,
          value: formatSleepMinutes(health.lastSleepMinutes),
          onTap: () => _googleHealthDetail(context, GoogleHealthMetric.sleep),
        );
      case TodayTile.heartRate:
        // Live from either source: the UI band reader OR the service isolate's
        // push (which owns the band while the app is backgrounded). Both land in
        // [latestHr]; [hasLiveHr] is the source-agnostic freshness flag.
        final live = health.hasLiveHr;
        final bpm = health.latestHr;
        return StatTile(
          icon: icon,
          labelKey: label,
          value: bpm == null ? '–' : sportInt(bpm),
          unit: bpm == null ? null : 'bpm',
          pulse: live,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HeartRatePage()),
          ),
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
      case TodayTile.hba1c:
        return _hba1cTile(context, icon, label);
    }
  }

  /// The newest lab result, or an em dash until one is entered — the box stays
  /// tappable either way, because an empty box that opens the page is how the
  /// user notes their first reading.
  StatTile _hba1cTile(BuildContext context, IconData icon, String label) {
    final latest = hba1c.latest;
    return StatTile(
      icon: icon,
      labelKey: label,
      value: latest == null ? '–' : sportDecimal(latest.percent, 1),
      unit: latest == null ? null : '%',
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const Hba1cPage())),
    );
  }

  StatTile _metric(
    BuildContext context,
    IconData icon,
    String label,
    int? value,
    String unit,
    GoogleHealthMetric metric,
  ) {
    return StatTile(
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
