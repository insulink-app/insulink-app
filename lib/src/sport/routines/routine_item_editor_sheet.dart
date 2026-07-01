import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/exercises/exercise_editor_sheet.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Zielwerte einer Übung in einer Routine bearbeiten: Sätze, Wiederholungen
/// bzw. Sekunden, Gewicht (nur bei Gewichts-Übungen) und Pausendauer.
Future<void> showRoutineItemEditorSheet(
  BuildContext context, {
  required String routineId,
  required int index,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<TrainingState>(),
      child: _RoutineItemEditorSheet(routineId: routineId, index: index),
    ),
  );
}

class _RoutineItemEditorSheet extends StatelessWidget {
  const _RoutineItemEditorSheet({required this.routineId, required this.index});

  final String routineId;
  final int index;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final routine = training.routineById(routineId);
    if (routine == null || index >= routine.items.length) {
      return const SizedBox.shrink();
    }
    final item = routine.items[index];
    final exercise = training.exerciseById(item.exerciseId);
    final isTimed = exercise?.kind == ExerciseKind.timed;
    final isWeighted = exercise?.kind == ExerciseKind.weighted;
    final accent = Theme.of(context).colorScheme.primary;

    return EditorSheet(
      titleKey: 'sport.routines.targets',
      valueText: exercise?.name ?? '',
      accent: accent,
      children: [
        _stepper(
          context,
          'sport.routines.sets',
          '${item.targetSets}',
          accent,
          (delta) => item.copyWith(
            targetSets: (item.targetSets + delta).clamp(1, 12),
          ),
        ),
        const SizedBox(height: 8),
        _stepper(
          context,
          isTimed ? 'sport.routines.seconds' : 'sport.routines.reps',
          isTimed ? '${item.target} s' : '${item.target}',
          accent,
          (delta) => item.copyWith(
            target: (item.target + delta * (isTimed ? 5 : 1)).clamp(1, 600),
          ),
        ),
        if (isWeighted) ...[
          const SizedBox(height: 8),
          _stepper(
            context,
            'sport.routines.weight',
            '${item.targetWeight.toStringAsFixed(1)} kg',
            accent,
            (delta) => item.copyWith(
              targetWeight: (item.targetWeight + delta * 2.5).clamp(0, 500),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _stepper(
          context,
          'sport.routines.rest',
          '${item.restSeconds} s',
          accent,
          (delta) => item.copyWith(
            restSeconds: (item.restSeconds + delta * 15).clamp(0, 600),
          ),
        ),
        if (exercise != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: LocaleText('sport.exercises.rename'),
              // Über den Navigator-Context öffnen, nicht über [context]: dieses
              // Sheet ist nach dem pop() deaktiviert, ein Provider-Lookup darauf
              // würde werfen ("deactivated widget's ancestor").
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                showExerciseEditorSheet(navigator.context, existing: exercise);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepper(
    BuildContext context,
    String labelKey,
    String valueText,
    Color accent,
    RoutineItem Function(int delta) apply,
  ) {
    void bump(int delta) {
      HapticFeedback.selectionClick();
      context.read<TrainingState>().updateRoutineItem(
        routineId,
        index,
        apply(delta),
      );
    }

    return GlucoseStepperRow(
      labelKey: labelKey,
      valueText: valueText,
      accent: accent,
      onMinus: () => bump(-1),
      onPlus: () => bump(1),
    );
  }
}
