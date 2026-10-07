import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// History overview of a daily Google Health metric (resting HR / sleep) from the
/// persistent Health archive — the Google Health analogue of [ActivityDetailPage]:
/// header (latest + average), a bar chart with range picker and a day list.
class GoogleHealthDetailPage extends StatefulWidget {
  const GoogleHealthDetailPage({super.key, required this.metric});

  final GoogleHealthMetric metric;

  @override
  State<GoogleHealthDetailPage> createState() => _GoogleHealthDetailPageState();
}

class _GoogleHealthDetailPageState extends State<GoogleHealthDetailPage> {
  SportRange _range = const SportRange.preset(30);

  String get _labelKey => switch (widget.metric) {
    GoogleHealthMetric.restingHr => 'google_health.resting_hr',
    GoogleHealthMetric.sleep => 'google_health.sleep',
    GoogleHealthMetric.respiratoryRate => 'google_health.respiratory_rate',
  };

  String? get _unit => switch (widget.metric) {
    GoogleHealthMetric.restingHr => 'bpm',
    GoogleHealthMetric.sleep => null,
    GoogleHealthMetric.respiratoryRate => 'rpm',
  };

  String _format(double value) => widget.metric == GoogleHealthMetric.sleep
      ? formatSleepMinutes(value.round())
      : sportInt(value.round());

  String _labeled(double value) =>
      _unit == null ? _format(value) : '${_format(value)} $_unit';

  List<GoogleHealthDay> _days(List<GoogleHealthDay> archive) {
    final now = DateTime.now();
    final from = _range.startFrom(now);
    final to = _range.endTo;
    return [
      for (final day in archive)
        if (day.value(widget.metric) != null &&
            (from == null ||
                !day.date.isBefore(
                  DateTime(from.year, from.month, from.day),
                )) &&
            (to == null || day.date.isBefore(to)))
          day,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final archive = context.watch<GoogleHealthState>().archive;
    final days = _days(archive);
    final scheme = Theme.of(context).colorScheme;
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
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                _header(context, scheme, days),
                const SizedBox(height: 20),
                SportRangeSelector(
                  value: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 16),
                _chartCard(scheme, days),
                const SizedBox(height: 24),
                LocaleText(
                  'sport.weight.history',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = days.length - 1; index >= 0; index--)
                  _dayRow(context, scheme, days[index]),
              ],
            ),
    );
  }

  double _value(GoogleHealthDay day) => day.value(widget.metric)!.toDouble();

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    List<GoogleHealthDay> days,
  ) {
    final avg = days.map(_value).reduce((a, b) => a + b) / days.length;
    final latest = _value(days.last);
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
          Text(
            _labeled(latest),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                PhosphorIconsBold.chartLine,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Locales.string(context, 'sport.activity.detail.average'),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _labeled(avg),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartCard(ColorScheme scheme, List<GoogleHealthDay> days) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: SizedBox(
        height: 200,
        child: ActivityBarChart<GoogleHealthDay>(
          days: days,
          date: (day) => day.date,
          value: _value,
          label: (day) => _labeled(_value(day)),
          color: scheme.primary,
        ),
      ),
    );
  }

  Widget _dayRow(
    BuildContext context,
    ColorScheme scheme,
    GoogleHealthDay day,
  ) {
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
              _labeled(_value(day)),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
