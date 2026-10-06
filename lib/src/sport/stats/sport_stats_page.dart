import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_leading_badge.dart';
import 'package:insulink/src/base/stat_tile.dart';
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
              children: [
                _summary(context, stats),
                const SizedBox(height: 28),
                SportStatsChartsView(
                  sessions: training.sessions,
                  routines: training.routines,
                ),
                const SizedBox(height: 28),
                _perExerciseHeader(context),
                const SizedBox(height: 12),
                for (final stat in exerciseStats) _exerciseCard(context, stat),
              ],
            ),
    );
  }

  /// 2×2 grid so each value has room (the three-across row clipped the numbers).
  Widget _summary(BuildContext context, SportStats stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: PhosphorIconsBold.barbell,
                labelKey: 'sport.stats.total_sessions',
                value: '${stats.totalSessions}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: PhosphorIconsBold.listChecks,
                labelKey: 'sport.stats.total_sets',
                value: '${stats.totalSets}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: PhosphorIconsBold.repeat,
                labelKey: 'sport.stats.total_reps',
                value: '${stats.totalReps}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: PhosphorIconsBold.timer,
                labelKey: 'sport.stats.total_time',
                value: '${stats.totalTrainingMinutes}',
                unit: Locales.string(context, 'sport.stats.min'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _perExerciseHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'sport.stats.per_exercise',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
    );
  }

  Widget _exerciseCard(BuildContext context, ExerciseStat stat) {
    final scheme = Theme.of(context).colorScheme;
    final lastAt = DateTime.fromMillisecondsSinceEpoch(stat.lastAtMs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ExerciseStatDetailPage(stat: stat),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                const SportLeadingBadge(icon: PhosphorIconsBold.barbell),
                const SizedBox(width: 14),
                Expanded(child: _titleBlock(context, stat, scheme, lastAt)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatScore(context, stat.best, stat.exercise.kind),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LocaleText(
                      'sport.stats.best',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBlock(
    BuildContext context,
    ExerciseStat stat,
    ColorScheme scheme,
    DateTime lastAt,
  ) {
    final subtitle = Locales.string(
      context,
      'sport.stats.card_subtitle',
      params: [
        '${stat.totalSets}',
        MaterialLocalizations.of(context).formatMediumDate(lastAt),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stat.exercise.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
