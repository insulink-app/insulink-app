import 'package:flutter/widgets.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// A set score rendered in its exercise kind's own unit: kg for weighted (est.
/// 1RM), seconds for timed, reps otherwise. A non-positive score reads as a
/// dash, so an exercise with no scoreable set shows "–" rather than "0".
String formatScore(BuildContext context, double score, ExerciseKind kind) {
  if (score <= 0) {
    return '–';
  }
  switch (kind) {
    case ExerciseKind.weighted:
      return '${score.toStringAsFixed(1)} ${Locales.string(context, 'sport.stats.kg')}';
    case ExerciseKind.timed:
      return Locales.string(
        context,
        'sport.stats.seconds',
        params: ['${score.round()}'],
      );
    case ExerciseKind.reps:
      return Locales.string(
        context,
        'sport.stats.reps',
        params: ['${score.round()}'],
      );
  }
}
