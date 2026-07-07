import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';

/// A logged activity — either a completed routine [session] or an endurance
/// [training] — unified so the shared logbook and home list can show both
/// merged by time. Exactly one of the two is non-null.
class ActivityEntry {
  final WorkoutSession? session;
  final CardioTraining? training;

  const ActivityEntry.routine(WorkoutSession this.session) : training = null;
  const ActivityEntry.cardio(CardioTraining this.training) : session = null;

  int get startMs => session?.startedAtMs ?? training!.startMs;
}

/// All logged routines and endurance trainings merged, newest first — the basis
/// for the shared logbook and the home "activities" list.
List<ActivityEntry> mergedActivities(
  List<WorkoutSession> sessions,
  List<CardioTraining> trainings,
) {
  final entries = <ActivityEntry>[
    for (final session in sessions) ActivityEntry.routine(session),
    for (final ride in trainings) ActivityEntry.cardio(ride),
  ];
  entries.sort((first, second) => second.startMs.compareTo(first.startMs));
  return entries;
}
