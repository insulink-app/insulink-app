import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The exercising phase: header (tap to jump), stopwatch, rep/weight inputs, the
/// "last time" comparison and the complete/finish buttons.
class WorkoutExerciseView extends StatelessWidget {
  const WorkoutExerciseView({
    super.key,
    required this.runner,
    required this.onJump,
    required this.onFinish,
  });

  final WorkoutRunner runner;
  final VoidCallback onJump;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Keeps the Spacer-centered layout when there is room but scrolls instead of
    // overflowing when space is tight (e.g. the keyboard covers half the screen
    // while editing reps).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, scheme),
                  const SizedBox(height: 8),
                  Text(
                    runner.currentExercise?.name ?? '—',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatDuration(runner.elapsed),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (runner.isTimed)
                    _targetTime(context, scheme)
                  else
                    _repWeightControls(context, scheme),
                  _lastTime(context, scheme),
                  const Spacer(),
                  FilledButton(
                    onPressed: runner.completeSet,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: LocaleText('sport.workout.complete_set'),
                  ),
                  TextButton(
                    onPressed: onFinish,
                    child: LocaleText('sport.workout.finish'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tapping the "exercise X/Y · set N/M" header opens the jump picker.
  Widget _header(BuildContext context, ColorScheme scheme) {
    return InkWell(
      onTap: onJump,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '${Locales.string(context, 'sport.workout.exercise')} '
          '${runner.exerciseIndex + 1}/${runner.totalExercises}  ·  '
          '${Locales.string(context, 'sport.workout.set')} '
          '${runner.setNumber}/${runner.totalSets}',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
      ),
    );
  }

  Widget _targetTime(BuildContext context, ColorScheme scheme) {
    return Text(
      Locales.string(
        context,
        'sport.workout.target_time',
        params: ['${runner.currentItem.target}'],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
    );
  }

  /// Enter the achieved reps inline (prefilled with the target); weight via +/-.
  Widget _repWeightControls(BuildContext context, ColorScheme scheme) {
    return Column(
      children: [
        LocaleText(
          'sport.routines.reps',
          style: TextStyle(
            fontSize: 14,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        SportEditableNumber(
          key: ValueKey('reps-${runner.exerciseIndex}-${runner.setNumber}'),
          valueText: '${runner.currentReps}',
          initial: runner.currentReps.toDouble(),
          min: 0,
          max: 999,
          width: 120,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
          onSubmit: (value) => runner.recordReps(value.round()),
        ),
        if (runner.isWeighted) ...[
          const SizedBox(height: 16),
          _weightRow(scheme),
        ],
      ],
    );
  }

  Widget _weightRow(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleIconButton(
          icon: PhosphorIconsBold.minus,
          accent: scheme.primary,
          onTap: () => runner.adjustWeight(-2.5),
        ),
        SizedBox(
          width: 120,
          child: Text(
            '${sportDecimal(runner.currentWeight, 1)} kg',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        CircleIconButton(
          icon: PhosphorIconsBold.plus,
          accent: scheme.primary,
          onTap: () => runner.adjustWeight(2.5),
        ),
      ],
    );
  }

  /// "Last time: …" from the same set of a previous session, if any.
  Widget _lastTime(BuildContext context, ColorScheme scheme) {
    final last = runner.lastComparable;
    if (last == null) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        Locales.string(
          context,
          'sport.workout.last_time',
          params: [_lastValue(last)],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }

  String _lastValue(SetLog set) {
    if (runner.isTimed) {
      return formatDuration(Duration(seconds: set.seconds ?? 0));
    }
    final reps = '${set.reps ?? 0}';
    final weight = set.weightKg;
    if (weight != null && weight > 0) {
      return '$reps × ${sportDecimal(weight, 1)} kg';
    }
    return reps;
  }
}
