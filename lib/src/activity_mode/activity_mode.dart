/// What the automation should expect glucose to do over the next stretch.
enum ActivityMode {
  /// No exercise: the loop doses to the user's own target and schedule.
  normal,

  /// Walking, running, cycling. Working muscle takes up glucose without
  /// insulin, so the loop aims higher and anchors on less basal.
  endurance,

  /// Lifting. Stress hormones tend to push glucose up during the set, so the
  /// basal is not reduced the way endurance reduces it.
  strength,
}

/// Why the current mode is what it is, shown beside it so a mode nobody chose
/// can be explained.
enum ActivityModeSource {
  /// Nothing going on, the mode is [ActivityMode.normal].
  none,

  /// Picked by hand, until [ActivityModeReading.until].
  manual,

  /// A routine workout is running.
  workout,

  /// A cardio training is being recorded.
  recording,

  /// The training detection sees a walk or ride going on.
  detected,
}

/// The mode in force, with where it came from.
class ActivityModeReading {
  const ActivityModeReading(this.mode, this.source, {this.until});

  static const normal = ActivityModeReading(
    ActivityMode.normal,
    ActivityModeSource.none,
  );

  final ActivityMode mode;
  final ActivityModeSource source;

  /// When a manual choice lapses; null for every other source.
  final DateTime? until;
}
