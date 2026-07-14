import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// History overview of a daily metric (steps/distance/calories) from the
/// persistent Health archive — analogous to the weight page: header metrics, a
/// bar chart with range picker and a day list (newest first).
class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({super.key, required this.metric});

  final ActivityMetric metric;

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  SportRange _range = const SportRange.preset(30);

  double _value(DailyActivity day) => switch (widget.metric) {
    ActivityMetric.steps => day.steps.toDouble(),
    ActivityMetric.distance => day.distanceKm,
    ActivityMetric.calories => day.calories,
  };

  String _format(double value) => switch (widget.metric) {
    ActivityMetric.steps => sportInt(value.round()),
    ActivityMetric.distance => sportDecimal(value, 2),
    ActivityMetric.calories => sportInt(value.round()),
  };

  String? get _unit => switch (widget.metric) {
    ActivityMetric.steps => null,
    ActivityMetric.distance => 'km',
    ActivityMetric.calories => 'kcal',
  };

  String get _labelKey => switch (widget.metric) {
    ActivityMetric.steps => 'sport.activity.steps',
    ActivityMetric.distance => 'sport.activity.distance',
    ActivityMetric.calories => 'sport.activity.calories',
  };

  List<DailyActivity> _inRange(List<DailyActivity> all) {
    final now = DateTime.now();
    final from = _range.startFrom(now);
    final to = _range.endTo;
    return [
      for (final day in all)
        if ((from == null ||
                !day.date.isBefore(
                  DateTime(from.year, from.month, from.day),
                )) &&
            (to == null || day.date.isBefore(to)))
          day,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final archive = context
        .watch<SportActivityState>()
        .activityArchiveWithToday(sport.strideCm, sport.latestWeight?.kg ?? 70);
    final ranged = _inRange(archive);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(_labelKey),
      ),
      body: archive.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsRegular.chartLineUp,
              titleKey: 'sport.activity.detail.empty',
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                _header(context, scheme, ranged),
                const SizedBox(height: 20),
                SportRangeSelector(
                  value: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 16),
                _chartCard(scheme, ranged),
                const SizedBox(height: 24),
                LocaleText(
                  'sport.weight.history',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = ranged.length - 1; index >= 0; index--)
                  _dayRow(context, scheme, ranged[index]),
              ],
            ),
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    List<DailyActivity> ranged,
  ) {
    final total = ranged.fold<double>(0, (sum, day) => sum + _value(day));
    final avg = ranged.isEmpty ? 0.0 : total / ranged.length;
    final latest = ranged.isEmpty ? 0.0 : _value(ranged.last);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            'sport.activity.detail.latest',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _format(latest),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_unit != null) ...[
                const SizedBox(width: 6),
                Text(
                  _unit!,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(
                context,
                scheme,
                PhosphorIconsRegular.chartLine,
                'sport.activity.detail.average',
                avg,
              ),
              _stat(
                context,
                scheme,
                PhosphorIconsRegular.function,
                'sport.activity.detail.total',
                total,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    ColorScheme scheme,
    IconData icon,
    String labelKey,
    double value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Locales.string(context, labelKey),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _unit == null ? _format(value) : '${_format(value)} $_unit',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chartCard(ColorScheme scheme, List<DailyActivity> ranged) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: SizedBox(
        height: 200,
        child: ranged.isEmpty
            ? Center(child: LocaleText('sport.activity.detail.empty'))
            : ActivityBarChart<DailyActivity>(
                days: ranged,
                date: (day) => day.date,
                value: _value,
                label: (day) => _unit == null
                    ? _format(_value(day))
                    : '${_format(_value(day))} $_unit',
                color: scheme.primary,
              ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, ColorScheme scheme, DailyActivity day) {
    final locale = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              locale.formatMediumDate(day.date),
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            Text(
              _unit == null
                  ? _format(_value(day))
                  : '${_format(_value(day))} $_unit',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
