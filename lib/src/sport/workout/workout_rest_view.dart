import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';

/// The resting phase: countdown (overtime once past 0, no auto-advance/tone),
/// the previous set's reps/weight still editable, and the extend/continue
/// buttons.
class WorkoutRestView extends StatelessWidget {
  const WorkoutRestView({
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          LocaleText(
            'sport.workout.rest',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          _countdown(scheme),
          const SizedBox(height: 12),
          _nextLine(context, scheme),
          const SizedBox(height: 24),
          _previousSetEditor(context, scheme),
          const Spacer(),
          _buttons(context),
          TextButton(
            onPressed: onFinish,
            child: LocaleText('sport.workout.finish'),
          ),
        ],
      ),
    );
  }

  Widget _countdown(ColorScheme scheme) {
    final expired = runner.restExpired;
    return Text(
      expired
          ? '+${formatDuration(runner.restOvertime)}'
          : formatDuration(runner.restRemaining),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.bold,
        color: expired ? scheme.error : scheme.primary,
      ),
    );
  }

  /// Tap to switch/select the upcoming exercise during the rest.
  Widget _nextLine(BuildContext context, ColorScheme scheme) {
    return InkWell(
      onTap: onJump,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                '${Locales.string(context, 'sport.workout.next')} '
                '${runner.currentExercise?.name ?? '—'}  ·  '
                '${Locales.string(context, 'sport.workout.set')} '
                '${runner.setNumber}/${runner.totalSets}',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.swap_horiz_rounded,
              size: 18,
              color: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// Correct the just-finished set here — reps (and weight, if it was weighted)
  /// are often only known after the set.
  Widget _previousSetEditor(BuildContext context, ColorScheme scheme) {
    final last = runner.lastLoggedSet;
    if (last == null || last.reps == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        LocaleText(
          'sport.workout.previous_set',
          style: TextStyle(
            fontSize: 14,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        SportEditableNumber(
          key: ValueKey('prev-reps-${last.atEpochMs}'),
          valueText: '${last.reps}',
          initial: last.reps!.toDouble(),
          min: 0,
          max: 999,
          width: 120,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          onSubmit: (value) => runner.updateLastSet(reps: value.round()),
        ),
        if (last.weightKg != null) ...[
          const SizedBox(height: 12),
          _weightRow(scheme, last.weightKg!),
        ],
      ],
    );
  }

  Widget _weightRow(ColorScheme scheme, double weight) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleIconButton(
          icon: Icons.remove,
          accent: scheme.primary,
          onTap: () => runner.updateLastSet(weightKg: (weight - 2.5).clamp(0, 999)),
        ),
        SizedBox(
          width: 120,
          child: Text(
            '${sportDecimal(weight, 1)} kg',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        CircleIconButton(
          icon: Icons.add,
          accent: scheme.primary,
          onTap: () => runner.updateLastSet(weightKg: (weight + 2.5).clamp(0, 999)),
        ),
      ],
    );
  }

  Widget _buttons(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    const textStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => runner.extendRest(60),
            icon: const Icon(Icons.more_time_rounded, size: 20),
            label: LocaleText('sport.workout.extend'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: shape,
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary, width: 1.5),
              textStyle: textStyle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: runner.skipRest,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: LocaleText('sport.workout.continue'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: shape,
              textStyle: textStyle,
            ),
          ),
        ),
      ],
    );
  }
}
