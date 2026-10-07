import 'dart:math' as math;
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// How the X-axis is bucketed/labelled, chosen from the window span.
enum HistoryBucket { hour, weekday, monthDay, month }

/// Aggregates the long-term archive into evenly-spaced buckets for the history
/// chart, picking the bucket granularity from the window [span]: hours for a day,
/// weekdays for up to two weeks, days-of-month up to a quarter, else months. Each
/// bucket is the mean glucose of its readings (in the display unit); empty
/// buckets leave a gap. Buckets are spanned over LOCAL calendar boundaries so the
/// labels read in the user's wall-clock time.
class GlucoseHistorySeries {
  GlucoseHistorySeries(this.archive, this.span, this.glucose);

  final SplayTreeMap<int, int> archive;
  final Duration span;
  final ProfileGlucoseState glucose;

  HistoryBucket get bucket {
    if (span.inHours <= 50) {
      return HistoryBucket.hour;
    }
    if (span.inDays <= 14) {
      return HistoryBucket.weekday;
    }
    if (span.inDays <= 92) {
      return HistoryBucket.monthDay;
    }
    return HistoryBucket.month;
  }

  /// The bucket-start times in order; `spots`' x is the index into this list, so
  /// the view labels a tick by looking up `starts[x]`.
  List<DateTime> get starts => _starts;
  List<DateTime> _starts = const [];

  /// The spread band around [build]'s means, one spot per non-empty bucket at
  /// mean ± one standard deviation. Filled by [build].
  List<FlSpot> get upperSpots => _upper;
  List<FlSpot> get lowerSpots => _lower;
  List<FlSpot> _upper = const [];
  List<FlSpot> _lower = const [];

  /// Mean-glucose spot per non-empty bucket (x = bucket index, y = display unit).
  List<FlSpot> build() {
    if (archive.isEmpty) {
      _starts = const [];
      _upper = const [];
      _lower = const [];
      return const [];
    }
    final kind = bucket;
    final first = _floor(_localOf(archive.firstKey()!), kind);
    final last = _floor(_localOf(archive.lastKey()!), kind);
    _starts = _spanStarts(first, last, kind);
    final indexOf = {
      for (var i = 0; i < _starts.length; i++)
        _starts[i].millisecondsSinceEpoch: i,
    };
    final sums = List<double>.filled(_starts.length, 0);
    final squares = List<double>.filled(_starts.length, 0);
    final counts = List<int>.filled(_starts.length, 0);
    archive.forEach((epochMin, mgdl) {
      final index =
          indexOf[_floor(_localOf(epochMin), kind).millisecondsSinceEpoch];
      if (index != null) {
        sums[index] += mgdl;
        squares[index] += mgdl * mgdl.toDouble();
        counts[index] += 1;
      }
    });
    _upper = _band(sums, squares, counts, 1);
    _lower = _band(sums, squares, counts, -1);
    return [
      for (var i = 0; i < _starts.length; i++)
        if (counts[i] > 0)
          FlSpot(
            i.toDouble(),
            glucose.toDisplay((sums[i] / counts[i]).round()),
          ),
    ];
  }

  /// Mean plus ([side] 1) or minus (-1) one standard deviation per bucket, from
  /// the running sums of values and squares.
  List<FlSpot> _band(
    List<double> sums,
    List<double> squares,
    List<int> counts,
    int side,
  ) {
    return [
      for (var index = 0; index < counts.length; index++)
        if (counts[index] > 0)
          FlSpot(
            index.toDouble(),
            glucose.toDisplay(
              (sums[index] / counts[index] +
                      side *
                          _deviation(
                            sums[index],
                            squares[index],
                            counts[index],
                          ))
                  .round()
                  .clamp(0, 400),
            ),
          ),
    ];
  }

  double _deviation(double sum, double square, int count) {
    final mean = sum / count;
    final variance = square / count - mean * mean;
    return variance <= 0 ? 0 : math.sqrt(variance);
  }

  DateTime _localOf(int epochMin) =>
      DateTime.fromMillisecondsSinceEpoch(epochMin * 60000);

  /// Truncate a time down to the start of its bucket.
  DateTime _floor(DateTime time, HistoryBucket kind) {
    switch (kind) {
      case HistoryBucket.hour:
        return DateTime(time.year, time.month, time.day, time.hour);
      case HistoryBucket.weekday:
      case HistoryBucket.monthDay:
        return DateTime(time.year, time.month, time.day);
      case HistoryBucket.month:
        return DateTime(time.year, time.month);
    }
  }

  /// The next bucket start after [start] (calendar-correct, so it survives DST,
  /// month and year boundaries).
  DateTime _next(DateTime start, HistoryBucket kind) {
    switch (kind) {
      case HistoryBucket.hour:
        return DateTime(start.year, start.month, start.day, start.hour + 1);
      case HistoryBucket.weekday:
      case HistoryBucket.monthDay:
        return DateTime(start.year, start.month, start.day + 1);
      case HistoryBucket.month:
        return DateTime(start.year, start.month + 1);
    }
  }

  List<DateTime> _spanStarts(
    DateTime first,
    DateTime last,
    HistoryBucket kind,
  ) {
    final out = <DateTime>[];
    var cursor = first;
    while (!cursor.isAfter(last) && out.length < 1000) {
      out.add(cursor);
      cursor = _next(cursor, kind);
    }
    return out;
  }
}
