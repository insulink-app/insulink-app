import 'package:insulink/src/google_health/google_health_models.dart';

/// Splits sleep-stage segments into the nights (or naps) they belong to.
///
/// Within one sleep session the stages follow each other with no gap, waking
/// included (it is a stage of its own), so a pause of [gap] or more between
/// one segment's end and the next one's start is a different session.
///
/// Grouping by session, not by the calendar day a SEGMENT ends on, is what
/// keeps a night together: a night from 23:52 to 07:41 used to be cut at
/// midnight, its first minutes landing on the previous day and mixing with
/// the night before ("fell asleep 23:59, woke up 23:52").
class SleepNights {
  const SleepNights(this.segments);

  final List<SleepSegment> segments;

  static const Duration gap = Duration(minutes: 90);

  /// Every session, each sorted by start, in the order they began.
  List<List<SleepSegment>> get all {
    final sorted = [...segments]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final nights = <List<SleepSegment>>[];
    var latestEnd = 0;
    for (final segment in sorted) {
      if (nights.isEmpty || segment.startMs - latestEnd >= gap.inMilliseconds) {
        nights.add([]);
        latestEnd = segment.endMs;
      }
      nights.last.add(segment);
      if (segment.endMs > latestEnd) {
        latestEnd = segment.endMs;
      }
    }
    return nights;
  }

  /// The longest session: the night, rather than a nap or a stray stretch of
  /// another night stored on the same day. Empty without segments.
  List<SleepSegment> get longest {
    List<SleepSegment> best = const [];
    var bestSpan = -1;
    for (final night in all) {
      final span = night.endMs - night.first.startMs;
      if (span > bestSpan) {
        best = night;
        bestSpan = span;
      }
    }
    return best;
  }
}

/// The span of one session of sleep segments.
extension SleepSessionSpan on List<SleepSegment> {
  /// Where the session ends: its latest end, not its last segment's, since
  /// segments are sorted by start and an earlier one can run on longer.
  int get endMs => map(
    (segment) => segment.endMs,
  ).reduce((latest, value) => value > latest ? value : latest);
}
