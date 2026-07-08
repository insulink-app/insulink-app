import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/sleep_hypnogram.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:provider/provider.dart';

/// History overview of a daily Google Health metric (resting HR / sleep / SpO2) from the
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
    GoogleHealthMetric.spo2 => 'google_health.spo2',
  };

  String? get _unit => switch (widget.metric) {
    GoogleHealthMetric.restingHr => 'bpm',
    GoogleHealthMetric.sleep => null,
    GoogleHealthMetric.spo2 => '%',
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
                !day.date.isBefore(DateTime(from.year, from.month, from.day))) &&
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
          ? Center(child: LocaleText('google_health.detail.empty'))
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                _header(context, scheme, days),
                if (_latestStages(days) != null) ...[
                  const SizedBox(height: 16),
                  _stagesCard(context, scheme, _latestStages(days)!),
                ],
                if (_latestTimeline(days) != null) ...[
                  const SizedBox(height: 16),
                  _hypnogramCard(context, scheme, _latestTimeline(days)!),
                ],
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

  /// Latest night's stage split, or null unless this is the sleep page and the
  /// most recent day carries stage records.
  SleepStages? _latestStages(List<GoogleHealthDay> days) {
    if (widget.metric != GoogleHealthMetric.sleep) {
      return null;
    }
    final stages = days.last.sleepStages;
    return stages != null && !stages.isEmpty ? stages : null;
  }

  /// Latest night's chronological stage timeline, or null unless this is the
  /// sleep page and the most recent day carries it.
  List<SleepSegment>? _latestTimeline(List<GoogleHealthDay> days) {
    if (widget.metric != GoogleHealthMetric.sleep) {
      return null;
    }
    final timeline = days.last.sleepTimeline;
    return timeline != null && timeline.isNotEmpty ? timeline : null;
  }

  /// The stage → colour map shared by the totals card and the hypnogram.
  Map<SleepStage, Color> _stageColors(ColorScheme scheme) => {
    SleepStage.deep: scheme.primary,
    SleepStage.rem: scheme.tertiary,
    SleepStage.light: scheme.primary.withValues(alpha: 0.45),
    SleepStage.awake: scheme.error.withValues(alpha: 0.7),
  };

  Widget _hypnogramCard(
    BuildContext context,
    ColorScheme scheme,
    List<SleepSegment> timeline,
  ) {
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
            'google_health.sleep_stage.timeline',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          SleepHypnogram(
            segments: timeline,
            colors: _stageColors(scheme),
            labels: {
              for (final stage in SleepStage.values)
                stage: Locales.string(
                  context,
                  'google_health.sleep_stage.${stage.name}',
                ),
            },
            axisColor: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  /// Deep / REM / Light / Awake, in the display order and colours of the card.
  List<({String key, Color color, int minutes})> _stageRows(
    ColorScheme scheme,
    SleepStages stages,
  ) => [
    (key: 'google_health.sleep_stage.deep', color: scheme.primary, minutes: stages.deep),
    (
      key: 'google_health.sleep_stage.rem',
      color: scheme.tertiary,
      minutes: stages.rem,
    ),
    (
      key: 'google_health.sleep_stage.light',
      color: scheme.primary.withValues(alpha: 0.45),
      minutes: stages.light,
    ),
    (
      key: 'google_health.sleep_stage.awake',
      color: scheme.error.withValues(alpha: 0.7),
      minutes: stages.awake,
    ),
  ];

  Widget _stagesCard(
    BuildContext context,
    ColorScheme scheme,
    SleepStages stages,
  ) {
    final rows = _stageRows(scheme, stages);
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
            'google_health.sleep_stage',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final row in rows)
                  if (row.minutes > 0)
                    Expanded(
                      flex: row.minutes,
                      child: Container(height: 12, color: row.color),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final row in rows) _stageRow(context, scheme, row),
        ],
      ),
    );
  }

  Widget _stageRow(
    BuildContext context,
    ColorScheme scheme,
    ({String key, Color color, int minutes}) row,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: row.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Locales.string(context, row.key),
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          Text(
            formatSleepMinutes(row.minutes),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme, List<GoogleHealthDay> days) {
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
              Icon(Icons.timeline_rounded, size: 16, color: scheme.primary),
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

  Widget _dayRow(BuildContext context, ColorScheme scheme, GoogleHealthDay day) {
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
