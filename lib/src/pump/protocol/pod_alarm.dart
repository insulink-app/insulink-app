/// What kind of problem an alarming pod is reporting, and therefore what the
/// user can do about it.
///
/// The pod has around 160 distinct alarm codes, but almost all of them are
/// internal firmware faults whose only remedy is the same one: take the pod off
/// and use a new one. Transcribing them all would be 160 constants carrying one
/// piece of information between them, so the raw code is kept verbatim in
/// [PodAlarm.rawCode] for reporting and this classifies it into the cases that
/// lead to genuinely different advice.
enum PodAlarmKind {
  /// No alarm.
  none,

  /// The cannula or the tubing is blocked. Insulin was not delivered.
  occlusion,

  /// The reservoir ran dry.
  emptyReservoir,

  /// The pod reached the end of its life.
  expired,

  /// The pod believes it delivered materially more or less than it was told to.
  /// The most safety-relevant class: what is in the log may not match the body.
  infusionError,

  /// An alert was left unacknowledged long enough for the pod to escalate it.
  escalatedAlert,

  /// The pod's own radio gave up on us.
  communication,

  /// An internal fault. Nothing to do but replace the pod.
  internalFault,
}

/// One pod alarm: the raw code the pod reported and what it means.
class PodAlarm {
  const PodAlarm(this.rawCode);

  /// The byte the pod sent. Kept so a user can quote the exact code even when
  /// this classifies it as a generic fault.
  final int rawCode;

  bool get isAlarming => rawCode != 0x00;

  PodAlarmKind get kind {
    if (rawCode == 0x00) {
      return PodAlarmKind.none;
    }
    if (rawCode == _occluded || _isOcclusionDetection(rawCode)) {
      return PodAlarmKind.occlusion;
    }
    if (rawCode == _emptyReservoir) {
      return PodAlarmKind.emptyReservoir;
    }
    if (rawCode == _pumpExpired) {
      return PodAlarmKind.expired;
    }
    if (rawCode >= _infusionErrorFirst && rawCode <= _infusionErrorLast) {
      return PodAlarmKind.infusionError;
    }
    if (rawCode >= _alertFirst && rawCode <= _alertLast) {
      return PodAlarmKind.escalatedAlert;
    }
    if (rawCode >= _bluetoothFirst) {
      return PodAlarmKind.communication;
    }
    return PodAlarmKind.internalFault;
  }

  /// Whether this alarm means delivery has certainly stopped. Every pod alarm
  /// stops delivery, so this is true whenever one is present — kept explicit
  /// because it is the fact the UI has to act on.
  bool get stopsDelivery => isAlarming;

  static const int _occluded = 0x14;
  static const int _emptyReservoir = 0x18;
  static const int _pumpExpired = 0x1c;
  static const int _alertFirst = 0x29;
  static const int _alertLast = 0x30;

  /// The occlusion-detection family: the checks the pod runs on its own pulse
  /// timing, all of which mean the same thing to the user as a plain occlusion.
  static const int _occlusionCheckFirst = 0x57;
  static const int _occlusionCheckLast = 0x6a;

  /// Over- and under-infusion on basal, temp basal and bolus.
  static const int _infusionErrorFirst = 0x80;
  static const int _infusionErrorLast = 0x8a;

  static const int _bluetoothFirst = 0xa0;

  static bool _isOcclusionDetection(int code) =>
      code >= _occlusionCheckFirst && code <= _occlusionCheckLast;

  @override
  String toString() =>
      'PodAlarm(0x${rawCode.toRadixString(16).padLeft(2, '0')}, ${kind.name})';
}
