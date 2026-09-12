part of 'pod_store.dart';

/// One thing the pod delivered, and why.
///
/// Kept per delivery rather than derived from the basal ledger, because these are
/// discrete events with a time the user recognises: a bolus they asked for, or the
/// two volumes an activation consumes. Basal is a continuous drip and belongs in
/// the ledger, not in a list of doses.
class PodDelivery {
  const PodDelivery({
    required this.at,
    required this.units,
    required this.kind,
  });

  factory PodDelivery.fromJson(Map<String, dynamic> json) => PodDelivery(
    at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
    units: (json['units'] as num).toDouble(),
    kind: PodDeliveryKind.values.firstWhere(
      (entry) => entry.name == json['kind'],
      orElse: () => PodDeliveryKind.bolus,
    ),
  );

  final DateTime at;
  final double units;
  final PodDeliveryKind kind;

  Map<String, dynamic> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'units': units,
    'kind': kind.name,
  };
}

/// What a recorded delivery was for. Named rather than a bare number, because
/// only one of these went into the user.
enum PodDeliveryKind {
  /// A dose the user asked for.
  bolus,

  /// The volume the pod pushed through its own mechanism before it went on the
  /// body. Never reaches the user, but it does leave the reservoir.
  prime,

  /// The volume used to drive the cannula in.
  cannula,
}

/// The log of everything the pod has delivered, newest first.
///
/// Local and pump-specific on purpose: a bolus also reaches the account as part
/// of a meal, but that record is about the meal. This one answers "what did this
/// pod actually put out, and when", including the volumes no meal will ever
/// mention.
extension PodDeliveryLog on PodStore {
  /// How many deliveries are kept. A pod lives 80 hours; this is more entries
  /// than one could plausibly produce, and it keeps secure storage bounded.
  static const int maxEntries = 200;

  /// Everything logged for the current pod, newest first.
  List<PodDelivery> get deliveryLog {
    final encoded = _cache[PodStore._kDeliveryLog];
    if (encoded == null || encoded.isEmpty) {
      return const [];
    }
    try {
      final entries = jsonDecode(encoded) as List<dynamic>;
      return [
        for (final entry in entries)
          PodDelivery.fromJson(entry as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Adds one delivery, newest first, dropping the oldest past [maxEntries].
  ///
  /// Written AFTER the pod confirmed the delivery, never before. This is a record
  /// of what happened, and an entry for a dose the pod refused would overstate
  /// the insulin on board.
  Future<void> recordDelivery(PodDelivery delivery) async {
    final entries = [delivery, ...deliveryLog];
    final kept = entries.length > maxEntries
        ? entries.sublist(0, maxEntries)
        : entries;
    await _set(
      PodStore._kDeliveryLog,
      jsonEncode([for (final entry in kept) entry.toJson()]),
    );
  }

  /// The bolus the pod is working through, or null when none is.
  ///
  /// Cleared as soon as it has run its course, so a stale record cannot leave a
  /// progress bar on screen forever.
  PodRunningBolus? get runningBolus {
    final encoded = _cache[PodStore._kRunningBolus];
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return PodRunningBolus.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> startRunningBolus(PodRunningBolus bolus) =>
      _set(PodStore._kRunningBolus, jsonEncode(bolus.toJson()));

  Future<void> clearRunningBolus() => _remove(PodStore._kRunningBolus);

  /// A bolus that has been asked for but not yet answered.
  ///
  /// Written BEFORE the command goes out, so a process that dies mid-send leaves
  /// a trace. Without it the app would restart with no idea that a dose might be
  /// running, which is the one thing it must never be unaware of.
  PodRunningBolus? get pendingBolus {
    final encoded = _cache[PodStore._kPendingBolus];
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return PodRunningBolus.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> startPendingBolus(PodRunningBolus request) =>
      _set(PodStore._kPendingBolus, jsonEncode(request.toJson()));

  Future<void> clearPendingBolus() => _remove(PodStore._kPendingBolus);

  /// Corrects a logged delivery to what the pod actually gave.
  ///
  /// Used when a bolus is stopped part-way: the entry was written for the full
  /// programmed dose, and leaving it there would credit the user with insulin
  /// they never received.
  Future<void> amendDelivery(DateTime at, double units) async {
    final entries = deliveryLog;
    final amended = [
      for (final entry in entries)
        if (entry.at == at)
          PodDelivery(at: entry.at, units: units, kind: entry.kind)
        else
          entry,
    ];
    await _set(
      PodStore._kDeliveryLog,
      jsonEncode([for (final entry in amended) entry.toJson()]),
    );
  }

  /// Units delivered as boluses within [window] of now.
  ///
  /// Only boluses count: the priming and cannula volumes never reached the user,
  /// so counting them against a dose limit would refuse insulin the user is owed.
  double bolusUnitsWithin(Duration window, {DateTime? now}) {
    final since = (now ?? DateTime.now()).subtract(window);
    return deliveryLog
        .where(
          (entry) =>
              entry.kind == PodDeliveryKind.bolus && entry.at.isAfter(since),
        )
        .fold<double>(0, (sum, entry) => sum + entry.units);
  }

  /// Boluses the pod may or may not have delivered.
  ///
  /// A bolus whose outcome is unknown is deliberately recorded in NEITHER the
  /// meal log nor [deliveryLog]. That is the right call for the user's own
  /// calculator: understating insulin there is recoverable by logging it
  /// afterwards, while overstating it would suppress a correction they need.
  ///
  /// The automation needs the opposite assumption and cannot ask anyone. If the
  /// dose did go in, a loop blind to it would add insulin on top of it, and the
  /// insulin the loop is allowed to add is computed from how much is already on
  /// board. So the possibility is kept here, read only by the loop, which treats
  /// it as delivered.
  ///
  /// The two readers disagreeing is the point: each assumes whatever is
  /// conservative for what it does next.
  List<PodDelivery> get unconfirmedBoluses {
    final encoded = _cache[PodStore._kUnconfirmedBoluses];
    if (encoded == null || encoded.isEmpty) {
      return const [];
    }
    try {
      return [
        for (final entry in jsonDecode(encoded) as List<dynamic>)
          PodDelivery.fromJson(entry as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Notes a bolus that may have been delivered, dropping any old enough that no
  /// insulin model would still count them.
  Future<void> recordUnconfirmedBolus(PodDelivery bolus) async {
    final cutoff = bolus.at.subtract(const Duration(hours: 24));
    final kept = [
      bolus,
      ...unconfirmedBoluses.where((entry) => entry.at.isAfter(cutoff)),
    ];
    await _set(
      PodStore._kUnconfirmedBoluses,
      jsonEncode([for (final entry in kept.take(20)) entry.toJson()]),
    );
  }

  /// Units still active from boluses that may have been delivered, decaying
  /// linearly over [insulinDuration] exactly as [ActiveInsulin] decays a bolus.
  double unconfirmedBolusUnits(Duration insulinDuration, {DateTime? now}) {
    final at = now ?? DateTime.now();
    var units = 0.0;
    for (final bolus in unconfirmedBoluses) {
      final elapsed = at.difference(bolus.at).inSeconds;
      final fraction = 1 - elapsed / insulinDuration.inSeconds;
      units += bolus.units * fraction.clamp(0.0, 1.0);
    }
    return units;
  }
}
