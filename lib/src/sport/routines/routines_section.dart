import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercises_page.dart';
import 'package:insulink/src/sport/logbook/workout_log_page.dart';
import 'package:insulink/src/sport/routines/routine_editor_page.dart';
import 'package:insulink/src/sport/sport_add_tile.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:provider/provider.dart';

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
                  icon: const Icon(Icons.history, size: 20),
                  tooltip: Locales.string(context, 'sport.logbook'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WorkoutLogPage(),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.fitness_center, size: 20),
                  tooltip: Locales.string(context, 'sport.exercises'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExercisesPage(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final routine in routines) _routineCard(context, routine),
        SportAddTile(
          labelKey: 'sport.routines.new',
          onTap: () => _create(context),
        ),
      ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        tileColor: scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        title: Text(
          routine.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          Locales.string(
            context,
            'sport.routines.count',
            params: ['${routine.items.length}'],
          ),
        ),
        trailing: routine.items.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.play_circle_fill,
                  size: 44,
                  color: scheme.primary,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkoutRunnerPage(routine: routine),
                  ),
                ),
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RoutineEditorPage(routineId: routine.id),
          ),
        ),
      ),
    );
  }
}
