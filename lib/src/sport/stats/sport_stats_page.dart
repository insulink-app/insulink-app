import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/stats/exercise_stat_detail_page.dart';
import 'package:insulink/src/sport/stats/sport_stat_format.dart';
import 'package:insulink/src/sport/stats/sport_stats.dart';
import 'package:insulink/src/sport/stats/sport_stats_charts_view.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The app's read of the web panel's exercise-statistics page: totals across all
/// workouts, and a per-exercise list (sortable) that opens each exercise's
/// progression.
class SportStatsPage extends StatefulWidget {
  const SportStatsPage({super.key});

  @override
  State<SportStatsPage> createState() => _SportStatsPageState();
}

class _SportStatsPageState extends State<SportStatsPage> {
  StatSort _sort = StatSort.last;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final stats = SportStats(training.sessions, training.exercises);
    final exerciseStats = sortStats(stats.build(), _sort);
    return Scaffold(
      appBar: AppBar(title: LocaleText('sport.stats.title')),
      body: exerciseStats.isEmpty
          ? EmptyState(
              icon: PhosphorIconsBold.chartLineUp,
              titleKey: 'sport.stats.empty',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                InkSpace.panelMargin,
                12,
                InkSpace.panelMargin,
                64,
              ),
              children: [
                _summary(context, stats),
                SportStatsChartsView(
                  sessions: training.sessions,
                  routines: training.routines,
                ),
                _perExerciseHeader(context),
                InkPanel.list(
                  rows: [
                    for (final stat in exerciseStats)
                      _exerciseRow(context, stat),
                  ],
                ),
              ],
            ),
    );
  }

  /// The four totals in one panel, two by two, parted by lines.
  Widget _summary(BuildContext context, SportStats stats) {
    return MetricGrid(
      icons: const [
        PhosphorIconsBold.barbell,
        PhosphorIconsBold.listChecks,
        PhosphorIconsBold.repeat,
        PhosphorIconsBold.timer,
      ],
      cells: [
        _cell(context, 'sport.stats.total_sessions', stats.totalSessions, null),
        _cell(context, 'sport.stats.total_sets', stats.totalSets, null),
        _cell(context, 'sport.stats.total_reps', stats.totalReps, null),
        _cell(
          context,
          'sport.stats.total_time',
          stats.totalTrainingMinutes,
          Locales.string(context, 'sport.stats.min'),
        ),
      ],
    );
  }

  MetricCell _cell(BuildContext context, String key, int value, String? unit) =>
      (label: Locales.string(context, key), value: sportInt(value), unit: unit);

  /// "Pro Übung" with the sort menu on the right.
  Widget _perExerciseHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SectionHeader(
        titleKey: 'sport.stats.per_exercise',
        actions: [
          PopupMenuButton<StatSort>(
            initialValue: _sort,
            onSelected: (sort) => setState(() => _sort = sort),
            icon: const Icon(PhosphorIconsBold.arrowsDownUp, size: 20),
            itemBuilder: (context) => [
              for (final sort in StatSort.values)
                PopupMenuItem(
                  value: sort,
                  child: LocaleText('sport.stats.sort_${sort.name}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// One exercise: barbell disc, name over "80 Sätze, zuletzt …", the best
  /// score on the right; opens its progression.
  Widget _exerciseRow(BuildContext context, ExerciseStat stat) {
    final colors = context.ink;
    final lastAt = DateTime.fromMillisecondsSinceEpoch(stat.lastAtMs);
    return ListRow(
      icon: PhosphorIconsBold.barbell,
      title: stat.exercise.name,
      subtitle: Locales.string(
        context,
        'sport.stats.card_subtitle',
        params: [
          '${stat.totalSets}',
          MaterialLocalizations.of(context).formatMediumDate(lastAt),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseStatDetailPage(stat: stat),
        ),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Text(
            formatScore(context, stat.best, stat.exercise.kind),
            style: InkText.rowTitle,
          ),
          LocaleText(
            'sport.stats.best',
            style: InkText.caption.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}
