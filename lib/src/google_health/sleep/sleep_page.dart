import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/sleep/sleep_hero_card.dart';
import 'package:insulink/src/google_health/sleep/sleep_history_panel.dart';
import 'package:insulink/src/google_health/sleep/sleep_index_panel.dart';
import 'package:insulink/src/base/day_pager.dart';
import 'package:insulink/src/google_health/sleep/sleep_phases_panel.dart';
import 'package:insulink/src/google_health/sleep/sleep_trend_section.dart';
import 'package:insulink/src/google_health/sleep_metrics.dart';
import 'package:insulink/src/google_health/sleep_targets_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/google_health/sleep_nights.dart';

/// The sleep page: one night in detail (stepped through with the pager) and
/// the nights of the chosen window as a trend and a list. Everything comes
/// from the Health archive; the target windows from [SleepTargets].
class SleepPage extends StatefulWidget {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  SportRange _range = const SportRange.preset(30);

  /// Which night is shown (`dateKey`); null = the latest.
  String? _selectedNightKey;

  /// Null until loaded; the index panel waits for it. Edited in the profile's
  /// sleep topic, so it is read again each time the page opens.
  SleepTargets? _targets;

  @override
  void initState() {
    super.initState();
    SleepTargets.load().then((targets) {
      if (mounted) {
        setState(() => _targets = targets);
      }
    });
  }

  List<GoogleHealthDay> _nights(List<GoogleHealthDay> archive) {
    final from = _range.startFrom(DateTime.now());
    final to = _range.endTo;
    return [
      for (final day in archive)
        if (day.value(GoogleHealthMetric.sleep) != null &&
            (from == null ||
                !day.date.isBefore(
                  DateTime(from.year, from.month, from.day),
                )) &&
            (to == null || day.date.isBefore(to)))
          day,
    ];
  }

  int _nightIndex(List<GoogleHealthDay> nights) {
    final found = nights.indexWhere((day) => day.dateKey == _selectedNightKey);
    return found >= 0 ? found : nights.length - 1;
  }

  int _minutes(GoogleHealthDay night) =>
      night.value(GoogleHealthMetric.sleep)!.round();

  @override
  Widget build(BuildContext context) {
    final nights = _nights(context.watch<GoogleHealthState>().archive);
    return Scaffold(
      appBar: AppBar(title: LocaleText('google_health.sleep')),
      body: nights.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsFill.moon,
              titleKey: 'google_health.detail.empty',
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              children: _sections(nights),
            ),
    );
  }

  List<Widget> _sections(List<GoogleHealthDay> nights) {
    final index = _nightIndex(nights);
    final night = nights[index];
    final average =
        nights.map(_minutes).reduce((sum, value) => sum + value) ~/
        nights.length;
    final stages = night.sleepStages;
    final hasStages = stages != null && !stages.isEmpty;
    final timeline = _timeline(night);
    final metrics = hasStages ? SleepMetrics.of(stages, timeline) : null;
    return [
      DayPager(
        previousLabelKey: 'google_health.sleep_page.previous_night',
        nextLabelKey: 'google_health.sleep_page.next_night',
        date: night.date,
        onPrevious: index > 0 ? () => _select(nights[index - 1]) : null,
        onNext: index < nights.length - 1
            ? () => _select(nights[index + 1])
            : null,
      ),
      const SizedBox(height: 14),
      SleepHeroCard(
        minutes: _minutes(night),
        averageMinutes: average,
        index: metrics?.sleepIndex,
        timeline: timeline,
      ),
      if (metrics != null && _targets != null) ...[
        _header(
          'google_health.sleep_stats.index',
          actions: [if (metrics.meets(_targets!)) const SleepAllInTargetHint()],
        ),
        SleepIndexPanel(metrics: metrics, targets: _targets!),
      ],
      if (hasStages) ...[
        _header('google_health.sleep_stage'),
        SleepPhasesPanel(stages: stages, timeline: timeline),
      ],
      _header('google_health.sleep_page.trend'),
      SleepTrendSection(
        range: _range,
        onRange: (range) => setState(() => _range = range),
        nights: nights,
        averageMinutes: average,
      ),
      _header('google_health.sleep_page.history'),
      SleepHistoryPanel(nights: nights),
    ];
  }

  /// The night's own session out of what was stored for the day. Days imported
  /// before the importer grouped by session can still carry a stretch of the
  /// next night (cut at midnight), which made the night read as falling asleep
  /// at 23:59 and waking at 23:52.
  List<SleepSegment>? _timeline(GoogleHealthDay night) {
    final stored = night.sleepTimeline;
    if (stored == null || stored.isEmpty) {
      return stored;
    }
    return SleepNights(stored).longest;
  }

  void _select(GoogleHealthDay night) =>
      setState(() => _selectedNightKey = night.dateKey);

  /// Section titles line up with the page text, 8 px inside the panels' edge.
  Widget _header(String titleKey, {List<Widget> actions = const []}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SectionHeader(titleKey: titleKey, actions: actions),
    );
  }
}
