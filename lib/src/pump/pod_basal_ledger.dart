part of 'pod_store.dart';

/// The basal side of [PodStore]: the schedule the pod is running, the temporary
/// rate overriding it, and the ledger of delivered windows waiting to be sent to
/// the account.
///
/// A `part` rather than its own class because it is the same keystore and the same
/// in-memory cache — splitting it into a wrapper would mean either duplicating that
/// plumbing or exposing it, and the ledger's whole value is that a window is
/// recorded and its mark advanced in ONE write.
extension PodBasalLedger on PodStore {
  /// The temporary basal rate the pod is running, if one was set.
  ///
  /// Kept even once its stretch has passed, until the ledger has billed past its
  /// end — dropping it the moment it expires would make the last window before
  /// expiry bill at the schedule instead of the temporary rate.
  PodTemporaryBasal? get temporaryBasal {
    final encoded = _cache[PodStore._kTempBasal];
    if (encoded == null) {
      return null;
    }
    try {
      return PodTemporaryBasal.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> saveTemporaryBasal(PodTemporaryBasal temporary) =>
      _set(PodStore._kTempBasal, jsonEncode(temporary.toJson()));

  Future<void> clearTemporaryBasal() => _remove(PodStore._kTempBasal);

  /// The hourly basal schedule the pod was programmed with, one U/h per hour.
  ///
  /// Stored rather than read from the user's profile, because this is the schedule
  /// the POD is running — the profile may have been edited since, and what the
  /// forecasting model needs is what was actually delivered.
  List<double>? get basalRates {
    final encoded = _cache[PodStore._kBasalRates];
    if (encoded == null) {
      return null;
    }
    try {
      final rates = (jsonDecode(encoded) as List)
          .map((rate) => (rate as num).toDouble())
          .toList();
      return rates.length == 24 ? rates : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveBasalRates(List<double> rates) =>
      _set(PodStore._kBasalRates, jsonEncode(rates));

  /// The user's own scheduled rate for the hour [at] falls in, or null when the
  /// app does not know the schedule the pod is running.
  ///
  /// Null rather than zero, deliberately. Zero is a real rate that means the pod
  /// is delivering nothing, and a screen that shows it because the schedule was
  /// never read would be claiming something it cannot know.
  double? scheduledUnitsPerHourAt(DateTime at) {
    final rates = basalRates;
    if (rates == null) {
      return null;
    }
    final rate = rates[at.hour];
    return rate.isFinite && rate >= 0 ? rate : null;
  }

  /// How far basal delivery has already been accounted for, so a window is never
  /// counted twice nor left out.
  DateTime? get basalCountedTo {
    final millis = int.tryParse(_cache[PodStore._kBasalCountedTo] ?? '');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Basal deliveries waiting to be sent to the account, as
  /// `{'at': epochMs, 'units': double}`.
  ///
  /// A queue rather than a fire-and-forget push: the service polls the pod while
  /// the phone may well have no connection, and a dropped sample is a hole in the
  /// model's insulin history that nothing later can fill.
  List<Map<String, dynamic>> get pendingBasalDeliveries {
    final encoded = _cache[PodStore._kBasalDelivered];
    if (encoded == null) {
      return const [];
    }
    try {
      return (jsonDecode(encoded) as List).cast<Map<String, dynamic>>();
    } on FormatException {
      return const [];
    }
  }

  /// Records a delivered window and moves the accounting mark to its end.
  ///
  /// Both in one step: a sample stored without moving the mark would be counted
  /// again on the next poll, and a mark moved without the sample would lose the
  /// insulin entirely.
  Future<void> addBasalDelivery({
    required DateTime at,
    required double units,
    required DateTime countedTo,
  }) async {
    if (units > 0) {
      final queue = [
        ...pendingBasalDeliveries,
        {'at': at.millisecondsSinceEpoch, 'units': units},
      ];
      final capped = queue.length > PodStore._maxPendingDeliveries
          ? queue.sublist(queue.length - PodStore._maxPendingDeliveries)
          : queue;
      await _set(PodStore._kBasalDelivered, jsonEncode(capped));
      // Kept apart from the queue above, which is drained the moment the account
      // accepts it. This is what the user is shown, and it has to survive that.
      await _set(PodStore._kBasalTotal, '${basalDeliveredTotal + units}');
      await _addBasalHour(at, units);
    }
    await _set(
      PodStore._kBasalCountedTo,
      '${countedTo.millisecondsSinceEpoch}',
    );
  }

  /// Basal booked per hour, oldest first, for the history page.
  ///
  /// Hourly rather than per booking: the watch books every quarter of an hour, and
  /// a pod's life would be three hundred rows of nothing anyone reads. An hour is
  /// the granularity a person actually thinks in.
  ///
  /// A separate record from the queue the account drains AND from the running
  /// total, because it answers a different question: not "how much", but "when".
  List<PodBasalHour> get basalHours {
    final encoded = _cache[PodStore._kBasalHours];
    if (encoded == null || encoded.isEmpty) {
      return const [];
    }
    try {
      final entries = jsonDecode(encoded) as List<dynamic>;
      return [
        for (final entry in entries)
          PodBasalHour.fromJson(entry as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Adds [units] to the hour [at] falls in, merging with what that hour already
  /// holds.
  Future<void> _addBasalHour(DateTime at, double units) async {
    final hour = DateTime(at.year, at.month, at.day, at.hour);
    final entries = [...basalHours];
    final index = entries.indexWhere((entry) => entry.hour == hour);
    if (index >= 0) {
      entries[index] = PodBasalHour(
        hour: hour,
        units: entries[index].units + units,
      );
    } else {
      entries.add(PodBasalHour(hour: hour, units: units));
    }
    final kept = entries.length > PodStore._maxBasalHours
        ? entries.sublist(entries.length - PodStore._maxBasalHours)
        : entries;
    await _set(
      PodStore._kBasalHours,
      jsonEncode([for (final entry in kept) entry.toJson()]),
    );
  }

  /// Every unit of basal this pod has delivered, as booked by the background
  /// watch.
  ///
  /// The same number the forecasting model is fed, not a fresh calculation off the
  /// schedule: a stretch the pod spent suspended is booked as the nothing it was,
  /// and re-deriving it from the schedule afterwards would quietly put it back.
  double get basalDeliveredTotal =>
      double.tryParse(_cache[PodStore._kBasalTotal] ?? '') ?? 0;

  /// Drops the samples the account has accepted.
  Future<void> clearBasalDeliveries(int count) async {
    final remaining = pendingBasalDeliveries.skip(count).toList();
    if (remaining.isEmpty) {
      await _remove(PodStore._kBasalDelivered);
      return;
    }
    await _set(PodStore._kBasalDelivered, jsonEncode(remaining));
  }

  /// Starts the accounting from [moment] without recording anything, used when a
  /// pod begins delivering.
  Future<void> startBasalAccounting(DateTime moment) =>
      _set(PodStore._kBasalCountedTo, '${moment.millisecondsSinceEpoch}');

  /// Roughly two days of 15-minute samples. Past that the oldest are dropped:
  /// insulin history that old is no longer shaping a forecast, and an unbounded
  /// queue in secure storage is its own problem.
}

/// One hour's worth of basal, as the background watch booked it.
///
/// The hour is a wall-clock hour, so it lines up with what the user reads on a
/// clock and with the schedule the pod runs its slots on.
class PodBasalHour {
  const PodBasalHour({required this.hour, required this.units});

  factory PodBasalHour.fromJson(Map<String, dynamic> json) => PodBasalHour(
    hour: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
    units: (json['units'] as num).toDouble(),
  );

  /// The start of the hour this covers.
  final DateTime hour;

  final double units;

  Map<String, dynamic> toJson() => {
    'at': hour.millisecondsSinceEpoch,
    'units': units,
  };
}
