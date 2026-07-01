import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_detail_page.dart';
import 'package:insulink/src/sport/activity/activity_settings_sheet.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
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
          _SummaryTile(
            icon: Icons.directions_walk,
            labelKey: 'sport.activity.steps',
            value: '$steps',
            onTap: () => _openDetail(context, ActivityMetric.steps),
          ),
          _SummaryTile(
            icon: Icons.straighten,
            labelKey: 'sport.activity.distance',
            value: distanceKm.toStringAsFixed(2),
            unit: 'km',
            onTap: () => _openDetail(context, ActivityMetric.distance),
          ),
        ),
        const SizedBox(height: 12),
        _row(
          _SummaryTile(
            icon: Icons.local_fire_department,
            labelKey: 'sport.activity.calories',
            value: '${calories.round()}',
            unit: 'kcal',
            onTap: () => _openDetail(context, ActivityMetric.calories),
          ),
          _SummaryTile(
            icon: Icons.monitor_weight,
            labelKey: 'sport.weight',
            value: latestWeight == null
                ? '–'
                : latestWeight.kg.toStringAsFixed(1),
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

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.labelKey,
    required this.value,
    this.unit,
    this.onTap,
  });

  final IconData icon;
  final String labelKey;
  final String value;
  final String? unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _iconBadge(scheme),
              const SizedBox(width: 12),
              Expanded(child: _text(context, scheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBadge(ColorScheme scheme) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: scheme.onPrimary),
    );
  }

  Widget _text(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Locales.string(context, labelKey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
