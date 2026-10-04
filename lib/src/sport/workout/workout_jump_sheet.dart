import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// What the "exercise X/Y · set N/M" header opens: skip or swap the current
/// exercise (while resting: the one coming up), jump to any exercise, or add
/// one. Every change applies to this session only.
class WorkoutJumpSheet extends StatelessWidget {
  const WorkoutJumpSheet({
    super.key,
    required this.runner,
    required this.onSwap,
    required this.onAdd,
  });

  final WorkoutRunner runner;
  final VoidCallback onSwap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final items = runner.routine.items;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          if (runner.canSkipExercise)
            _action(
              context,
              PhosphorIconsBold.skipForward,
              'sport.workout.skip_exercise',
              runner.skipExercise,
            ),
          if (!runner.awaitingNextExercise)
            _action(
              context,
              PhosphorIconsBold.arrowsLeftRight,
              'sport.workout.swap_exercise',
              onSwap,
            ),
          const Divider(height: 1),
          for (var index = 0; index < items.length; index++)
            _exerciseTile(context, index),
          _action(
            context,
            PhosphorIconsBold.plus,
            'sport.workout.add_exercise',
            onAdd,
          ),
        ],
      ),
    );
  }

  /// One action row; closes the sheet before acting, so a follow-up page (the
  /// exercise picker) opens on top of the runner, not of the sheet.
  Widget _action(
    BuildContext context,
    IconData icon,
    String labelKey,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: LocaleText(labelKey),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );
  }

  Widget _exerciseTile(BuildContext context, int index) {
    final training = context.read<TrainingState>();
    final item = runner.routine.items[index];
    return ListTile(
      leading: index == runner.exerciseIndex
          ? const Icon(PhosphorIconsFill.play)
          : const SizedBox(width: 24),
      title: Text(training.exerciseById(item.exerciseId)?.name ?? '—'),
      onTap: () {
        runner.jumpTo(index);
        Navigator.of(context).pop();
      },
    );
  }
}
