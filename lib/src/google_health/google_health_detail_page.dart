import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/sleep_hypnogram.dart';
import 'package:insulink/src/google_health/sleep_stats_card.dart';
import 'package:insulink/src/google_health/sleep_targets_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

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

  /// Which night the sleep stages + hypnogram show (`dateKey`); null = latest.
  String? _selectedNightKey;

  /// The sleep target windows for the stat bars; null until loaded (stats card
  /// simply waits for it). Edited in the profile "Sleep" topic — reloaded here
  /// each time the page opens.
  SleepTargets? _sleepTargets;

  @override
  void initState() {
    super.initState();
    if (widget.metric == GoogleHealthMetric.sleep) {
      SleepTargets.load().then((targets) {
        if (mounted) {
          setState(() => _sleepTargets = targets);
        }
      });
    }
  }

  String get _labelKey => switch (widget.metric) {
    GoogleHealthMetric.restingHr => 'google_health.resting_hr',
    GoogleHealthMetric.sleep => 'google_health.sleep',
    GoogleHealthMetric.spo2 => 'google_health.spo2',
    GoogleHealthMetric.respiratoryRate => 'google_health.respiratory_rate',
  };

  String? get _unit => switch (widget.metric) {
    GoogleHealthMetric.restingHr => 'bpm',
    GoogleHealthMetric.sleep => null,
    GoogleHealthMetric.spo2 => '%',
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
                ..._sleepSection(context, scheme, days),
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

  /// The sleep page's stage cards for the selected night, with a day pager —
  /// empty for non-sleep metrics or when no night carries stage records.
  List<Widget> _sleepSection(
    BuildContext context,
    ColorScheme scheme,
    List<GoogleHealthDay> days,
  ) {
    if (widget.metric != GoogleHealthMetric.sleep) {
      return const [];
    }
    final nights = [
      for (final day in days)
        if (day.sleepStages != null && !day.sleepStages!.isEmpty) day,
    ];
    if (nights.isEmpty) {
      return const [];
    }
    final index = _nightIndex(nights);
    final night = nights[index];
    return [
      const SizedBox(height: 16),
      _nightPager(context, scheme, nights, index),
      const SizedBox(height: 12),
      if (_sleepTargets != null) ...[
        SleepStatsCard(
          stages: night.sleepStages!,
          timeline: night.sleepTimeline,
          targets: _sleepTargets!,
        ),
        const SizedBox(height: 16),
      ],
      _stagesCard(context, scheme, night.sleepStages!),
      if (night.sleepTimeline != null && night.sleepTimeline!.isNotEmpty) ...[
        const SizedBox(height: 16),
        _hypnogramCard(context, scheme, night.sleepTimeline!),
      ],
    ];
  }

  /// Index of the selected night in [nights], defaulting to the latest.
  int _nightIndex(List<GoogleHealthDay> nights) {
    final found = nights.indexWhere((day) => day.dateKey == _selectedNightKey);
    return found >= 0 ? found : nights.length - 1;
  }

  /// ‹ date › pager to step through nights (chevrons disabled at the ends).
  Widget _nightPager(
    BuildContext context,
    ColorScheme scheme,
    List<GoogleHealthDay> nights,
    int index,
  ) {
    void select(int next) =>
        setState(() => _selectedNightKey = nights[next].dateKey);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.caretLeft),
          onPressed: index > 0 ? () => select(index - 1) : null,
        ),
        Text(
          MaterialLocalizations.of(
            context,
          ).formatMediumDate(nights[index].date),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        IconButton(
          icon: const Icon(PhosphorIconsBold.caretRight),
          onPressed: index < nights.length - 1 ? () => select(index + 1) : null,
        ),
      ],
    );
  }

  /// Fixed, conventional sleep-stage colours (deep→awake), distinct in both
  /// light and dark — the single source of truth for the totals card AND the
  /// hypnogram. Theme-derived colours collided here (primary == tertiary), so
  /// deep and REM looked identical.
  static const Map<SleepStage, Color> _stageColors = {
    SleepStage.deep: Color(0xFF7C4DFF), // violet
    SleepStage.light: Color(0xFF4FC3F7), // light blue
    SleepStage.rem: Color(0xFF1DE9B6), // turquoise
    SleepStage.awake: Color(0xFFEF5350), // light red
    SleepStage.restless: Color(0xFFF06292), // pink
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
            colors: _stageColors,
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

  /// Stage rows in display order (deepest first), each with its colour + minutes.
  List<({String key, Color color, int minutes})> _stageRows(
    SleepStages stages,
  ) => [
    (
      key: 'google_health.sleep_stage.deep',
      color: _stageColors[SleepStage.deep]!,
      minutes: stages.deep,
    ),
    (
      key: 'google_health.sleep_stage.light',
      color: _stageColors[SleepStage.light]!,
      minutes: stages.light,
    ),
    (
      key: 'google_health.sleep_stage.rem',
      color: _stageColors[SleepStage.rem]!,
      minutes: stages.rem,
    ),
    (
      key: 'google_health.sleep_stage.restless',
      color: _stageColors[SleepStage.restless]!,
      minutes: stages.restless,
    ),
    (
      key: 'google_health.sleep_stage.awake',
      color: _stageColors[SleepStage.awake]!,
      minutes: stages.awake,
    ),
  ];

  Widget _stagesCard(
    BuildContext context,
    ColorScheme scheme,
    SleepStages stages,
  ) {
    final rows = _stageRows(stages);
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
          for (final row in rows)
            if (row.minutes > 0) _stageRow(context, scheme, row),
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
