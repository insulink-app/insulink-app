import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/daily_history/daily_history_view.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// History of a daily activity metric (steps/distance/calories) from the
/// persistent Health archive, measured against its daily goal from the
/// activity goals (screen 43).
class ActivityDetailPage extends StatelessWidget {
  const ActivityDetailPage({super.key, required this.metric});

  final ActivityMetric metric;

  double _value(DailyActivity day) => switch (metric) {
    ActivityMetric.steps => day.steps.toDouble(),
    ActivityMetric.distance => day.distanceKm,
    ActivityMetric.calories => day.calories,
  };

  String get _labelKey => switch (metric) {
    ActivityMetric.steps => 'sport.activity.steps',
    ActivityMetric.distance => 'sport.activity.distance',
    ActivityMetric.calories => 'sport.activity.calories',
  };

  DailyMetric _metric(SportState sport) => switch (metric) {
    ActivityMetric.steps => DailyMetric(
      format: (value) => sportInt(value.round()),
      goal: sport.stepsGoal.toDouble(),
    ),
    ActivityMetric.distance => DailyMetric(
      format: (value) => sportDecimal(value, 2),
      unit: 'km',
      goal: sport.distanceGoalKm,
    ),
    ActivityMetric.calories => DailyMetric(
      format: (value) => sportInt(value.round()),
      unit: 'kcal',
      goal: sport.caloriesGoal.toDouble(),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final archive = context
        .watch<SportActivityState>()
        .activityArchiveWithToday(sport.strideCm, sport.latestWeight?.kg ?? 70);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(_labelKey),
      ),
      body: archive.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsBold.chartLineUp,
              titleKey: 'sport.activity.detail.empty',
            )
          : DailyHistoryView(
              days: [
                for (final day in archive) (date: day.date, value: _value(day)),
              ],
              metric: _metric(sport),
            ),
    );
  }
}
