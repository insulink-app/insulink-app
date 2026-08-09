import 'package:flutter/widgets.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// What a logged workout is called wherever it is listed: its routine's name,
/// the free-training label when it ran without a routine, and the
/// deleted-routine notice when the routine it names is gone.
String workoutSessionTitle(BuildContext context, WorkoutSession session) {
  if (session.routineId == freeRoutineId) {
    return Locales.string(context, 'sport.workout.free');
  }
  return context.read<TrainingState>().routineById(session.routineId)?.name ??
      Locales.string(context, 'sport.logbook.deleted_routine');
}
