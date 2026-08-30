import 'dart:collection';

/// Reads the glucose archive at a wall-clock moment, taking the nearest reading
/// rather than demanding one on that exact minute.
///
/// This is the bug that made every suggestion say "not enough data" whatever the
/// window. The archive is keyed by the minute a reading ACTUALLY happened, and a
/// CGM delivers every five minutes on its own phase, so asking for 03:00 sharp
/// misses four times out of five. Both analyses ask at hour boundaries and at
/// logged dose times, so nearly every hour and every dose window was dropped for
/// having no reading, and no window was ever long enough to fix it.
///
/// [tolerance] is a little over one CGM cadence, so a normal gap between two
/// readings is always covered and a genuine hole still reads as missing, which
/// is what both finders rely on to drop an hour they cannot measure.
class TuningGlucose {
  const TuningGlucose(this.archive, {this.tolerance = const Duration(minutes: 6)});

  /// The archive slice, keyed by epoch-minute (`CgmStore.archiveRange`).
  final SplayTreeMap<int, int> archive;

  final Duration tolerance;

  /// The reading at [moment], or null when nothing is close enough to it.
  int? at(DateTime moment) {
    final minute = moment.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final exact = archive[minute];
    if (exact != null) {
      return exact;
    }
    final before = archive.lastKeyBefore(minute);
    final after = archive.firstKeyAfter(minute);
    final nearest = _nearer(minute, before, after);
    if (nearest == null || (nearest - minute).abs() > tolerance.inMinutes) {
      return null;
    }
    return archive[nearest];
  }

  int? _nearer(int minute, int? before, int? after) {
    if (before == null || after == null) {
      return before ?? after;
    }
    return minute - before <= after - minute ? before : after;
  }
}
