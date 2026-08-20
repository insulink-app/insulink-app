import 'dart:collection';
import 'dart:typed_data';

import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';

/// A glucose archive ending at [now] with [mgdl], sloping at [trendPerMinute].
///
/// Built as real archive rows so the tests exercise the same validation and the
/// same regression the loop runs on, rather than a hand-made input object that
/// could not fail the checks.
///
/// Steps of five minutes with whole-number slopes keep every sample an exact
/// integer, so the recovered trend is the one asked for and a test can assert on
/// a dose without a rounding allowance.
SplayTreeMap<int, int> archiveEndingAt(
  DateTime now, {
  required int mgdl,
  double trendPerMinute = 0,
  int points = 5,
  int stepMinutes = 5,
}) {
  final newestMinute = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
  final archive = SplayTreeMap<int, int>();
  for (var step = 0; step < points; step++) {
    final minutesBack = step * stepMinutes;
    archive[newestMinute - minutesBack] =
        (mgdl - trendPerMinute * minutesBack).round();
  }
  return archive;
}

LoopGlucose glucoseAt(
  DateTime now, {
  required int mgdl,
  double trendPerMinute = 0,
}) {
  return LoopGlucose.from(
    archiveEndingAt(now, mgdl: mgdl, trendPerMinute: trendPerMinute),
    now: now,
  );
}

/// Limits with everything at a plain default, so a test names only what it is
/// actually about.
LoopLimits limitsWith({
  int targetMgdl = 110,
  int suspendBelowMgdl = 85,
  int correctionFactorMgdl = 35,
  Duration insulinDuration = const Duration(hours: 3),
  double maxUnitsPerHour = 3.0,
  double maxIobUnits = 5.0,
}) {
  return LoopLimits(
    targetMgdl: targetMgdl,
    suspendBelowMgdl: suspendBelowMgdl,
    correctionFactorMgdl: correctionFactorMgdl,
    insulinDuration: insulinDuration,
    maxUnitsPerHour: maxUnitsPerHour,
    maxIobUnits: maxIobUnits,
  );
}

/// Decodes a captured pod frame. The pump tests each carry their own copy of
/// this; the loop tests share this one.
Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);
