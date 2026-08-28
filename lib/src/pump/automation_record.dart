part of 'pod_store.dart';

/// The hours in which the automation delivered above the user's schedule, kept
/// for as long as the analysis might ask about them.
///
/// Separate from the pod's own basal ledger, and deliberately NOT cleared by
/// [PodStore.forgetPod]. The ledger belongs to a pod and dies with it, and a pod
/// lives eighty hours, so anything resting on it resets every three days and is
/// empty the morning after a pod change. This is the user's insulin history, not
/// the pod's, and the basal analysis needs to be able to ask about hours from
/// weeks ago.
///
/// Only hours that actually carried excess are stored, which is a small fraction
/// of them. What makes the record complete is [automationCoveredSince]: from
/// that moment on, an hour with no entry is an hour with no excess, and the
/// difference between "nothing happened" and "nothing was written down" stops
/// mattering. Before it, nothing can be said either way.
extension PodAutomationRecord on PodStore {
  /// The most hours kept. Ninety days of hours would be a large blob in a
  /// keystore; ninety days of hours that CARRIED EXCESS is a small one, and this
  /// is generous even for a loop that runs hot every night.
  static const int maxHours = 400;

  /// When this record started being kept. Null before the first booking, which
  /// means nothing can be cleared yet.
  DateTime? get automationCoveredSince {
    final millis = int.tryParse(_cache[PodStore._kAutomationSince] ?? '');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Excess units the automation delivered during [hour], or 0.
  ///
  /// Zero means one of two things and the caller has to tell them apart with
  /// [automationCoveredSince]: inside the covered span it means no excess ran,
  /// before it that nothing is known.
  double automationExcessInHour(DateTime hour) {
    final key = _automationKeyOf(hour);
    return _automationHours()[key] ?? 0;
  }

  /// Starts the covered span, at the first moment the automation could deliver
  /// anything. Does nothing once started.
  ///
  /// Called when the automation is switched on rather than on the first booking:
  /// booking runs for every pod user, including one who never turns the
  /// automation on, and stamping it there would make the analysis demand a
  /// clearance for hours that had nothing to clear.
  Future<void> startAutomationRecord() async {
    if (automationCoveredSince != null) {
      return;
    }
    final now = DateTime.now();
    await _set(
      PodStore._kAutomationSince,
      '${DateTime(now.year, now.month, now.day, now.hour).millisecondsSinceEpoch}',
    );
  }

  /// Notes excess delivered in the hour [at] falls in.
  ///
  /// A no-op before the record has been started, which is the state of anyone
  /// who has never switched the automation on.
  Future<void> recordAutomationExcess(DateTime at, double excess) async {
    if (excess <= 0 || automationCoveredSince == null) {
      return;
    }
    final hours = _automationHours();
    final key = _automationKeyOf(at);
    hours[key] = (hours[key] ?? 0) + excess;
    final kept = hours.length > maxHours
        ? Map<String, double>.fromEntries(
            (hours.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
                .skip(hours.length - maxHours),
          )
        : hours;
    await _set(PodStore._kAutomationHours, jsonEncode(kept));
  }

  Map<String, double> _automationHours() {
    final encoded = _cache[PodStore._kAutomationHours];
    if (encoded == null || encoded.isEmpty) {
      return <String, double>{};
    }
    try {
      return (jsonDecode(encoded) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    } on FormatException {
      return <String, double>{};
    }
  }

  /// Epoch-hour as the key, so the map sorts chronologically as text and stays
  /// compact.
  String _automationKeyOf(DateTime moment) =>
      '${moment.millisecondsSinceEpoch ~/ Duration.millisecondsPerHour}';
}
