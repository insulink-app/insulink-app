/// How much basal insulin a schedule delivers over a window of time.
///
/// This is what lets the forecasting model see basal at all. Boluses already
/// reach it as meal records, but basal is a continuous drip that is often about
/// half of a day's insulin — a model that cannot see it is modelling insulin on
/// board from roughly half the insulin.
///
/// Deliberately derived from the schedule the pod was PROGRAMMED with rather than
/// from the pod's own delivery counter. The counter is cumulative and includes
/// boluses, so differencing it and feeding the result alongside the meal records
/// would count every bolus twice — a worse error than the small metering
/// difference this ignores.
class PodBasalDelivery {
  const PodBasalDelivery(this.hourlyRates, {this.temporary});

  /// One rate in U/h per hour of the day, as [BasalProfile.rates] holds them.
  final List<double> hourlyRates;

  /// A temporary rate overriding the schedule for part of the window, if one was
  /// running. Without it a temp-basal stretch would be booked at the scheduled
  /// rate — the model would then see insulin the pod did not deliver, which is
  /// exactly the case a temp basal exists to create.
  final PodTemporaryBasal? temporary;

  static const int hoursPerDay = 24;

  /// Units delivered between [from] and [to], following the schedule across as
  /// many midnights as the window spans.
  ///
  /// Returns 0 for an empty or reversed window rather than a negative amount: a
  /// negative insulin sample would poison every feature derived from it.
  double unitsBetween(DateTime from, DateTime to) {
    if (hourlyRates.length != hoursPerDay || !to.isAfter(from)) {
      return 0;
    }
    var units = 0.0;
    var cursor = from;
    while (cursor.isBefore(to)) {
      final segmentEnd = _nextBoundary(cursor, to);
      final minutes =
          segmentEnd.difference(cursor).inMicroseconds /
          Duration.microsecondsPerMinute;
      units += _rateAt(cursor) * minutes / 60.0;
      cursor = segmentEnd;
    }
    return units;
  }

  /// The rate running at [moment], in U/h: the temporary one while it covers the
  /// moment, else the schedule's.
  double _rateAt(DateTime moment) {
    final override = temporary;
    if (override != null && override.covers(moment)) {
      return override.unitsPerHour;
    }
    final rate = hourlyRates[moment.hour];
    return rate.isFinite && rate > 0 ? rate : 0;
  }

  /// Where the rate can next change: the next hour boundary, the start or end of
  /// the temporary rate, or the end of the window — whichever comes first.
  ///
  /// Splitting at every one of those is what keeps a temp basal that starts or
  /// ends mid-hour billed correctly on both sides of the change.
  DateTime _nextBoundary(DateTime cursor, DateTime windowEnd) {
    var boundary = _nextHourBoundary(cursor);
    final override = temporary;
    if (override != null) {
      for (final edge in [override.start, override.end]) {
        if (edge.isAfter(cursor) && edge.isBefore(boundary)) {
          boundary = edge;
        }
      }
    }
    return boundary.isBefore(windowEnd) ? boundary : windowEnd;
  }

  /// The start of the next wall-clock hour. Wall-clock, not a fixed 60 minutes,
  /// so a daylight-saving change shifts the schedule with the clock the user
  /// reads — which is the same clock the pod runs its slots on.
  DateTime _nextHourBoundary(DateTime moment) {
    final hourStart = DateTime(
      moment.year,
      moment.month,
      moment.day,
      moment.hour,
    );
    return hourStart.add(const Duration(hours: 1));
  }

  /// The whole day's basal, for cross-checking a schedule against the pod's own
  /// reported daily total.
  double get dailyUnits => hourlyRates.fold<double>(
    0,
    (sum, rate) => sum + (rate.isFinite ? rate : 0),
  );
}

/// A temporary basal rate and the stretch it covers.
///
/// Held so the delivery ledger can bill that stretch at the rate the pod was
/// actually running, and so a rate of zero — the common "suspend basal for sport"
/// case — is booked as the nothing it is rather than as the schedule.
class PodTemporaryBasal {
  const PodTemporaryBasal({
    required this.unitsPerHour,
    required this.start,
    required this.end,
    this.automated = false,
  });

  factory PodTemporaryBasal.fromJson(Map<String, dynamic> json) {
    return PodTemporaryBasal(
      unitsPerHour: (json['units_per_hour'] as num).toDouble(),
      start: DateTime.fromMillisecondsSinceEpoch(
        (json['start'] as num).toInt(),
      ),
      end: DateTime.fromMillisecondsSinceEpoch((json['end'] as num).toInt()),
      automated: json['automated'] == true,
    );
  }

  final double unitsPerHour;
  final DateTime start;
  final DateTime end;

  /// Whether the automation set this, rather than the user.
  ///
  /// The ledger does not care, but the automation does: a rate the USER chose is
  /// an instruction, and replacing it on the next cycle would quietly undo the
  /// temp basal someone set before going running. Defaults to false so a rate
  /// stored before this existed is treated as the user's, which is the reading
  /// that leaves it alone.
  final bool automated;

  Map<String, dynamic> toJson() => {
    'units_per_hour': unitsPerHour,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    if (automated) 'automated': true,
  };

  /// Whether [moment] falls inside the stretch. The end is exclusive, so the
  /// schedule resumes exactly when the pod does.
  bool covers(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  /// A copy that stops at [moment], for a temp basal the user cancelled early.
  PodTemporaryBasal endedAt(DateTime moment) => PodTemporaryBasal(
    unitsPerHour: unitsPerHour,
    start: start,
    end: moment.isBefore(start) ? start : moment,
    automated: automated,
  );
}
