import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/activity_settings_sheet.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/weight/weight_detail_page.dart';
import 'package:provider/provider.dart';

/// "Today" section: 2×2 grid of steps (real), estimated distance + calories and
/// the current weight (tappable → weight history). Distance = steps × stride;
/// calories ≈ distance × weight × 0.9 (walking estimate).
class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final activity = context.watch<SportActivityState>();
    final sport = context.watch<SportState>();
    final steps = activity.todaySteps;
    final weightKg = sport.latestWeight?.kg ?? 70;
    final distanceKm =
        activity.importedDistanceKm ?? steps * sport.strideCm / 100000;
    final calories = activity.importedCalories ?? distanceKm * weightKg * 0.9;
    final latestWeight = sport.latestWeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 12),
        _row(
          SportSummaryTile(
            icon: Icons.directions_walk,
            labelKey: 'sport.activity.steps',
            value: sportInt(steps),
            onTap: () => _openDetail(context, ActivityMetric.steps),
          ),
          SportSummaryTile(
            icon: Icons.straighten,
            labelKey: 'sport.activity.distance',
            value: sportDecimal(distanceKm, 2),
            unit: 'km',
            onTap: () => _openDetail(context, ActivityMetric.distance),
          ),
        ),
        const SizedBox(height: 12),
        _row(
          SportSummaryTile(
            icon: Icons.local_fire_department,
            labelKey: 'sport.activity.calories',
            value: sportInt(calories.round()),
            unit: 'kcal',
            onTap: () => _openDetail(context, ActivityMetric.calories),
          ),
          SportSummaryTile(
            icon: Icons.monitor_weight,
            labelKey: 'sport.weight',
            value: latestWeight == null
                ? '–'
                : sportDecimal(latestWeight.kg, 1),
            unit: latestWeight == null ? null : 'kg',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WeightDetailPage()),
            ),
          ),
        ),
        if (activity.permissionDenied) ...[
          const SizedBox(height: 10),
          LocaleText(
            'sport.activity.permission',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  void _openDetail(BuildContext context, ActivityMetric metric) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityDetailPage(metric: metric),
      ),
    );
  }

  Widget _row(Widget left, Widget right) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'sport.today',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => showActivitySettingsSheet(context),
        ),
      ],
    );
  }
}
