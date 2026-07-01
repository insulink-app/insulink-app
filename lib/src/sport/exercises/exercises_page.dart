import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercise_editor_sheet.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Übungs-Bibliothek. Doppelt genutzt: ohne [onPick] zum Verwalten (tippen =
/// bearbeiten), mit [onPick] als Auswahl beim Hinzufügen zu einer Routine.
class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key, this.onPick});

  final void Function(SportExercise exercise)? onPick;

  @override
  Widget build(BuildContext context) {
    final exercises = context.watch<TrainingState>().exercises;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.exercises'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'exercise-add',
        onPressed: () => showExerciseEditorSheet(context),
        child: const Icon(Icons.add),
      ),
      body: exercises.isEmpty
          ? Center(child: LocaleText('sport.exercises.empty'))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [for (final ex in exercises) _row(context, ex)],
            ),
    );
  }

  Widget _row(BuildContext context, SportExercise exercise) {
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
          exercise.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          Locales.string(context, 'sport.exercises.kind.${exercise.kind.name}'),
        ),
        trailing: onPick == null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => confirmDelete(
                  context,
                  messageKey: 'sport.exercises.delete_confirm',
                  onConfirm: () =>
                      context.read<TrainingState>().removeExercise(exercise.id),
                ),
              )
            : const Icon(Icons.chevron_right),
        onTap: onPick == null
            ? () => showExerciseEditorSheet(context, existing: exercise)
            : () {
                onPick!(exercise);
                Navigator.of(context).pop();
              },
      ),
    );
  }
}
