import 'dart:typed_data';

/// What the pod is currently doing with insulin, as reported in every status.
enum PodDeliveryStatus {
  suspended(0x00),
  basalActive(0x01),
  tempBasalActive(0x02),
  priming(0x04),
  bolusAndBasalActive(0x05),
  bolusAndTempBasalActive(0x06),
  unknown(0xff);

  const PodDeliveryStatus(this.value);

  final int value;

  static PodDeliveryStatus byValue(int value) => PodDeliveryStatus.values
      .firstWhere((entry) => entry.value == value, orElse: () => unknown);

  bool get isBolusing =>
      this == bolusAndBasalActive || this == bolusAndTempBasalActive;

  bool get isBasalRunning => this == basalActive || this == bolusAndBasalActive;

  bool get isTempBasalRunning =>
      this == tempBasalActive || this == bolusAndTempBasalActive;

  bool get isSuspended => this == suspended;
}

/// Where the pod is in its lifecycle, from filled to deactivated.
enum PodLifecycleStatus {
  uninitialized(0x00),
  manufacturingTest(0x01),
  filled(0x02),
  uniqueIdSet(0x03),
  engagingClutchDrive(0x04),
  clutchDriveEngaged(0x05),
  basalProgramSet(0x06),
  priming(0x07),
  runningAboveMinimumVolume(0x08),
  runningBelowMinimumVolume(0x09),
  alarm(0x0d),
  lumpOfCoal(0x0e),
  deactivated(0x0f),
  unknown(0xff);

  const PodLifecycleStatus(this.value);

  final int value;

  static PodLifecycleStatus byValue(int value) => PodLifecycleStatus.values
      .firstWhere((entry) => entry.value == value, orElse: () => unknown);

  bool get isRunning =>
      this == runningAboveMinimumVolume || this == runningBelowMinimumVolume;

  /// Whether the pod can still be commanded. A pod in [alarm] or [deactivated]
  /// rejects delivery commands, so the UI has to route the user to a pod change
  /// instead of retrying.
  bool get acceptsDelivery => isRunning || this == basalProgramSet;
}

/// The audible confirmation a command asks the pod to make.
enum PodBeep {
  silent(0x00),
  fourTimesBipBeep(0x02),
  duringSuspend(0x04),
  longSingleBeep(0x06);

  const PodBeep(this.value);

  final int value;
}

/// The pod's own alert slots, reported as a bit set in every status.
enum PodAlert {
  autoOff(0),
  multiCommand(1),
  expirationImminent(2),
  userSetExpiration(3),
  lowReservoir(4),
  suspendInProgress(5),
  suspendEnded(6),
  expiration(7);

  const PodAlert(this.bit);

  final int bit;

  int get mask => 1 << bit;

  static Set<PodAlert> decode(int encoded) =>
      PodAlert.values.where((alert) => encoded & alert.mask != 0).toSet();

  static int encode(Set<PodAlert> alerts) =>
      alerts.fold<int>(0, (bits, alert) => bits | alert.mask);
}

/// Why the pod refused a command. [illegalSecurityCode] is the nonce/sequence
/// desync case and is the only one that carries a resync counter instead of an
/// alarm.
enum PodNakError {
  flashWrite(0x01),
  flashErase(0x02),
  flashOperation(0x03),
  flashAddress(0x04),
  podState(0x05),
  criticalVariable(0x06),
  illegalParameter(0x07),
  bolusCriticalVariable(0x08),
  internalIllegalParameter(0x09),
  illegalChecksum(0x0a),
  invalidMessageLength(0x0b),
  pumpState(0x0c),
  illegalCommand(0x0d),
  illegalFillState(0x0e),
  maxReadWriteSize(0x0f),
  illegalReadAddress(0x10),
  illegalReadMemoryType(0x11),
  initPod(0x12),
  illegalCommandState(0x13),
  illegalSecurityCode(0x14),
  podInAlarm(0x15),
  commandNotSet(0x16),
  illegalReceiverSensitivity(0x17),
  illegalTransmitPacketSize(0x18),
  occlusionParametersAlreadySet(0x19),
  occlusionParameter(0x1a),
  illegalOcclusionThreshold(0x1b),
  ignoreCommand(0x1c),
  invalidCrc(0x1d),
  unknown(0xff);

  const PodNakError(this.value);

  final int value;

  static PodNakError byValue(int value) => PodNakError.values
      .firstWhere((entry) => entry.value == value, orElse: () => unknown);
}

/// The reminder beeps a delivery program asks for.
class PodProgramReminder {
  const PodProgramReminder({
    this.atStart = false,
    this.atEnd = false,
    this.everyMinutes = 0,
  });

  final bool atStart;
  final bool atEnd;
  final int everyMinutes;

  Uint8List get encoded => Uint8List.fromList([
        ((atStart ? 1 : 0) << 7) | ((atEnd ? 1 : 0) << 6) | (everyMinutes & 0x3f),
      ]);
}
