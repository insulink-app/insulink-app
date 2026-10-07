import 'dart:ui';

import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The order the sleep page lists stages in: deepest first.
const List<SleepStage> sleepStageListOrder = [
  SleepStage.deep,
  SleepStage.light,
  SleepStage.rem,
  SleepStage.restless,
  SleepStage.awake,
];

/// How a sleep stage is shown: its colour, its names, and its share of a night.
extension SleepStageStyle on SleepStage {
  /// One colour per stage for the strip, the hypnogram and the list alike.
  Color colorIn(InsulinkColors colors) => switch (this) {
    SleepStage.deep => colors.sleepDeep,
    SleepStage.light => colors.sleepLight,
    SleepStage.rem => colors.sleepRem,
    SleepStage.restless => colors.sleepRestless,
    SleepStage.awake => colors.low,
  };

  /// The full name, for the stage list.
  String get nameKey => 'google_health.sleep_stage.$name';

  /// The short name, for the hypnogram's narrow lane labels.
  String get shortKey => 'google_health.sleep_stage.short.$name';

  int minutesIn(SleepStages stages) => switch (this) {
    SleepStage.deep => stages.deep,
    SleepStage.light => stages.light,
    SleepStage.rem => stages.rem,
    SleepStage.restless => stages.restless,
    SleepStage.awake => stages.awake,
  };
}
