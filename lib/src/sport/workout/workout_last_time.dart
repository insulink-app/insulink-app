import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';

/// "Last time: …", the matching set from this routine's previous run. Shown
/// while exercising and already during the rest before the set, so the number
/// to beat is known before it starts. Empty when there is nothing to compare.
class WorkoutLastTime extends StatelessWidget {
  const WorkoutLastTime({super.key, required this.runner});

  final WorkoutRunner runner;

  @override
  Widget build(BuildContext context) {
    final last = runner.lastComparable;
    if (last == null) {
      return const SizedBox(height: 8);
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        Locales.string(
          context,
          'sport.workout.last_time',
          params: [_describe(last)],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }

  String _describe(SetLog set) {
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
