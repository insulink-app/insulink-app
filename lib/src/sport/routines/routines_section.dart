import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercises_page.dart';
import 'package:insulink/src/sport/routines/routine_duration.dart';
import 'package:insulink/src/sport/routines/routine_editor_page.dart';
import 'package:insulink/src/sport/sport_add_tile.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_leading_badge.dart';
import 'package:insulink/src/sport/sport_menu.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/stats/sport_stats_page.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// "Routines" section of the sport home page: list of routines (tap = edit, play
/// = start), plus access to the exercise library and "+ Routine".
class RoutinesSection extends StatelessWidget {
  const RoutinesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final routines = context.watch<TrainingState>().routines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LocaleText(
              'sport.routines',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(PhosphorIconsBold.chartLineUp, size: 20),
                  tooltip: Locales.string(context, 'sport.stats.title'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SportStatsPage(),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(PhosphorIconsBold.barbell, size: 20),
                  tooltip: Locales.string(context, 'sport.exercises'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ExercisesPage()),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          proxyDecorator: (child, index, animation) =>
              Material(color: Colors.transparent, child: child),
          onReorderItem: (oldIndex, newIndex) =>
              context.read<TrainingState>().reorderRoutines(oldIndex, newIndex),
          children: [
            for (final routine in routines) _routineCard(context, routine),
          ],
        ),
        SportAddTile(
          labelKey: 'sport.routines.new',
          onTap: () => _create(context),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(PhosphorIconsFill.play, size: 16),
          label: LocaleText('sport.workout.free'),
          onPressed: () => _startFree(context),
        ),
      ],
    );
  }

  /// Start a workout with no routine behind it: its exercises are picked while
  /// it runs and nothing is written back to the library.
  void _startFree(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutRunnerPage(
          routine: SportRoutine(
            id: freeRoutineId,
            name: Locales.string(context, 'sport.workout.free'),
            items: const [],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final navigator = Navigator.of(context);
    final training = context.read<TrainingState>();
    final routine = await training.addRoutine(
      Locales.string(context, 'sport.routines.new'),
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => RoutineEditorPage(routineId: routine.id),
      ),
    );
  }

  Widget _routineCard(BuildContext context, SportRoutine routine) {
    final scheme = Theme.of(context).colorScheme;
    final training = context.read<TrainingState>();
    final hasItems = routine.items.isNotEmpty;
    return Padding(
      key: ValueKey(routine.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoutineEditorPage(routineId: routine.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                const SportLeadingBadge(icon: PhosphorIconsBold.barbell),
                const SizedBox(width: 14),
                Expanded(
                  child: _titleBlock(context, routine, training, scheme),
                ),
                if (hasItems) _playButton(context, routine, scheme),
                SportRowMenu(
                  onCopy: () => training.duplicateRoutine(
                    routine.id,
                    Locales.string(context, 'sport.copy_suffix'),
                  ),
                  deleteConfirmKey: 'sport.routines.delete_confirm',
                  onDelete: () => training.removeRoutine(routine.id),
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
    SportRoutine routine,
    TrainingState training,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          routine.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          _subtitle(context, routine, training),
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  String _subtitle(
    BuildContext context,
    SportRoutine routine,
    TrainingState training,
  ) {
    final count = Locales.string(
      context,
      'sport.routines.count',
      params: ['${routine.items.length}'],
    );
    if (routine.items.isEmpty) {
      return count;
    }
    final seconds = estimatedRoutineSeconds(
      routine,
      training.exercises,
      training.sessions,
    );
    final duration = Locales.string(
      context,
      'sport.routines.est_duration',
      params: [sportClock(seconds)],
    );
    return '$count · $duration';
  }

  Widget _playButton(
    BuildContext context,
    SportRoutine routine,
    ColorScheme scheme,
  ) {
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutRunnerPage(routine: routine),
          ),
        ),
        // Padding absorbs what the glyph gives up, so the button keeps its
        // 38px diameter and only the icon inside it shrinks.
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            PhosphorIconsFill.play,
            size: 14,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
