import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/daily_history/daily_history_view.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// History of a daily Google Health metric (resting HR / sleep / breathing rate)
/// from the persistent Health archive, in the shared daily-history layout. These
/// are rates, not totals, so the page leads with the latest day and the spread.
class GoogleHealthDetailPage extends StatelessWidget {
  const GoogleHealthDetailPage({super.key, required this.metric});

  final GoogleHealthMetric metric;

  String get _labelKey => switch (metric) {
    GoogleHealthMetric.restingHr => 'google_health.resting_hr',
    GoogleHealthMetric.sleep => 'google_health.sleep',
    GoogleHealthMetric.respiratoryRate => 'google_health.respiratory_rate',
  };

  DailyMetric get _metric => DailyMetric(
    format: (value) => metric == GoogleHealthMetric.sleep
        ? formatSleepMinutes(value.round())
        : sportInt(value.round()),
    unit: switch (metric) {
      GoogleHealthMetric.restingHr => 'bpm',
      GoogleHealthMetric.sleep => null,
      GoogleHealthMetric.respiratoryRate => 'rpm',
    },
    summed: false,
  );

  @override
  Widget build(BuildContext context) {
    final days = [
      for (final day in context.watch<GoogleHealthState>().archive)
        if (day.value(metric) != null)
          (date: day.date, value: day.value(metric)!.toDouble()),
    ];
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(_labelKey),
      ),
      body: days.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsFill.heart,
              titleKey: 'google_health.detail.empty',
            )
          : DailyHistoryView(days: days, metric: _metric),
    );
  }
}
