import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Edit an exercise's target values in a routine: sets, reps or seconds, weight
/// (weighted exercises only) and rest duration. Each value can be changed with
/// +/- OR by tapping it (direct number entry).
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
          labelKey: 'sport.routines.sets',
          valueText: '${item.targetSets}',
          accent: accent,
          current: item.targetSets.toDouble(),
          min: 1,
          max: 12,
          step: 1,
          apply: (value) => item.copyWith(targetSets: value.round()),
        ),
        const SizedBox(height: 8),
        _stepper(
          context,
          labelKey: isTimed ? 'sport.routines.seconds' : 'sport.routines.reps',
          valueText: isTimed ? '${item.target} s' : '${item.target}',
          accent: accent,
          current: item.target.toDouble(),
          min: 1,
          max: 600,
          step: isTimed ? 5 : 1,
          apply: (value) => item.copyWith(target: value.round()),
        ),
        if (isWeighted) ...[
          const SizedBox(height: 8),
          _stepper(
            context,
            labelKey: 'sport.routines.weight',
            valueText: '${sportDecimal(item.targetWeight, 1)} kg',
            accent: accent,
            current: item.targetWeight,
            min: 0,
            max: 500,
            step: 2.5,
            decimal: true,
            apply: (value) => item.copyWith(targetWeight: value),
          ),
        ],
        const SizedBox(height: 8),
        _stepper(
          context,
          labelKey: 'sport.routines.rest',
          valueText: '${item.restSeconds} s',
          accent: accent,
          current: item.restSeconds.toDouble(),
          min: 0,
          max: 600,
          step: 15,
          apply: (value) => item.copyWith(restSeconds: value.round()),
        ),
      ],
    );
  }

  Widget _stepper(
    BuildContext context, {
    required String labelKey,
    required String valueText,
    required Color accent,
    required double current,
    required double min,
    required double max,
    required double step,
    bool decimal = false,
    required RoutineItem Function(double value) apply,
  }) {
    void set(double value) {
      HapticFeedback.selectionClick();
      context.read<TrainingState>().updateRoutineItem(
        routineId,
        index,
        apply(value.clamp(min, max).toDouble()),
      );
    }

    return GlucoseStepperRow(
      labelKey: labelKey,
      valueText: valueText,
      accent: accent,
      onMinus: () => set(current - step),
      onPlus: () => set(current + step),
      valueChild: SportEditableNumber(
        key: ValueKey('$labelKey-$valueText'),
        valueText: valueText,
        initial: current,
        min: min,
        max: max,
        decimal: decimal,
        onSubmit: set,
      ),
    );
  }
}
