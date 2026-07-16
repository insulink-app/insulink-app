import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercise_editor_sheet.dart';
import 'package:insulink/src/sport/sport_menu.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Exercise library. Dual-use: without [onPick] for managing (tap = edit,
/// drag = reorder), with [onPick] as a picker when adding to a routine.
class ExercisesPage extends StatelessWidget {
  const ExercisesPage({super.key, this.onPick});

  final void Function(SportExercise exercise)? onPick;

  static const _bouncy = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );
  static const _padding = EdgeInsets.fromLTRB(20, 20, 20, 96);

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
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: exercises.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsBold.barbell,
              titleKey: 'sport.exercises.empty',
            )
          : onPick == null
          ? _reorderable(context, exercises)
          : _picker(context, exercises),
    );
  }

  Widget _reorderable(BuildContext context, List<SportExercise> exercises) {
    return ReorderableListView(
      physics: _bouncy,
      padding: _padding,
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, child: child),
      onReorderItem: (oldIndex, newIndex) =>
          context.read<TrainingState>().reorderExercises(oldIndex, newIndex),
      children: [
        for (var index = 0; index < exercises.length; index++)
          _manageRow(context, exercises[index], index),
      ],
    );
  }

  Widget _picker(BuildContext context, List<SportExercise> exercises) {
    return ListView(
      physics: _bouncy,
      padding: _padding,
      children: [for (final exercise in exercises) _pickRow(context, exercise)],
    );
  }

  Widget _manageRow(BuildContext context, SportExercise exercise, int index) {
    return Padding(
      key: ValueKey(exercise.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: _tile(
        context,
        exercise,
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(
            PhosphorIconsBold.dotsSixVertical,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        trailing: SportRowMenu(
          onCopy: () => context.read<TrainingState>().duplicateExercise(
            exercise.id,
            Locales.string(context, 'sport.copy_suffix'),
          ),
          deleteConfirmKey: 'sport.exercises.delete_confirm',
          onDelete: () =>
              context.read<TrainingState>().removeExercise(exercise.id),
        ),
        onTap: () => showExerciseEditorSheet(context, existing: exercise),
      ),
    );
  }

  Widget _pickRow(BuildContext context, SportExercise exercise) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _tile(
        context,
        exercise,
        trailing: const Icon(PhosphorIconsBold.caretRight),
        onTap: () {
          onPick!(exercise);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    SportExercise exercise, {
    Widget? leading,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // Background on the Container (not ListTile.tileColor) so it follows the
    // reorder transform instead of lagging behind — see routine_editor_page.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        leading: leading,
        title: Text(
          exercise.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          Locales.string(context, 'sport.exercises.kind.${exercise.kind.name}'),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
