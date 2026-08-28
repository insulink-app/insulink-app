/// How far an activation has got. Persisted, because an activation that is
/// interrupted must RESUME rather than restart: several of these steps deliver
/// insulin or are one-shot on the pod, so repeating them is not harmless.
enum PodActivationStep {
  notStarted,
  gotVersion,
  identitySet,
  activationAlertSet,
  priming,
  primed,
  basalSet,
  lifecycleAlertsSet,
  insertingCannula,
  running;

  bool isBefore(PodActivationStep other) => index < other.index;
}

/// Raised when an activation cannot continue.
class PodActivationException implements Exception {
  PodActivationException(this.message);

  final String message;

  @override
  String toString() => 'PodActivationException: $message';
}

/// What the pod told us about itself during activation, needed by later steps.
class PodActivationFacts {
  const PodActivationFacts({
    required this.uniqueId,
    required this.lotNumber,
    required this.podSequenceNumber,
    required this.primePulses,
    required this.cannulaInsertionPulses,
    required this.primePumpRateEighthSeconds,
    required this.expirationHours,
  });

  final int uniqueId;
  final int lotNumber;
  final int podSequenceNumber;
  final int primePulses;
  final int cannulaInsertionPulses;
  final int primePumpRateEighthSeconds;
  final int expirationHours;

  factory PodActivationFacts.fromJson(Map<String, dynamic> json) {
    return PodActivationFacts(
      uniqueId: (json['unique_id'] as num).toInt(),
      lotNumber: (json['lot_number'] as num).toInt(),
      podSequenceNumber: (json['pod_sequence_number'] as num).toInt(),
      primePulses: (json['prime_pulses'] as num).toInt(),
      cannulaInsertionPulses: (json['cannula_insertion_pulses'] as num).toInt(),
      primePumpRateEighthSeconds:
          (json['prime_pump_rate_eighth_seconds'] as num).toInt(),
      expirationHours: (json['expiration_hours'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'unique_id': uniqueId,
        'lot_number': lotNumber,
        'pod_sequence_number': podSequenceNumber,
        'prime_pulses': primePulses,
        'cannula_insertion_pulses': cannulaInsertionPulses,
        'prime_pump_rate_eighth_seconds': primePumpRateEighthSeconds,
        'expiration_hours': expirationHours,
      };

  /// How long a pulse train of [pulses] takes at the pod's prime rate.
  Duration deliveryTimeFor(int pulses) {
    final eighthSeconds = pulses * primePumpRateEighthSeconds;
    return Duration(milliseconds: eighthSeconds * 125);
  }
}
