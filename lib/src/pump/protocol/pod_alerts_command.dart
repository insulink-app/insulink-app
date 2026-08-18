import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// How insistently the pod repeats an alert. The values are the pod's; the names
/// describe where each one is used, since the protocol does not name them.
enum PodBeepRepetition {
  onceEveryMinuteForThreeMinutes(0x01),
  everyMinuteAndEveryFifteen(0x03),
  everyHour(0x05),
  onceOnly(0x06),
  everyFifteenMinutes(0x08);

  const PodBeepRepetition(this.value);

  final int value;
}

/// What makes an alert fire: a delay from now, or the reservoir dropping below a
/// volume.
class PodAlertTrigger {
  const PodAlertTrigger.afterMinutes(int minutes)
      : value = minutes,
        onReservoir = false;

  /// [microLitres] is compared against the reservoir; 200 is roughly 20 U at the
  /// pod's 0.05 U pulse.
  const PodAlertTrigger.belowReservoir(int microLitres)
      : value = microLitres,
        onReservoir = true;

  final int value;
  final bool onReservoir;
}

/// One alert slot's configuration.
class PodAlertConfiguration {
  const PodAlertConfiguration({
    required this.type,
    required this.trigger,
    this.enabled = true,
    this.durationMinutes = 0,
    this.autoOff = false,
    this.beep = PodBeep.fourTimesBipBeep,
    this.repetition = PodBeepRepetition.onceOnly,
  });

  final PodAlert type;
  final PodAlertTrigger trigger;
  final bool enabled;

  /// How long the alert keeps sounding. The field is 9 bits, split across the
  /// low bit of the first byte and the whole second byte.
  final int durationMinutes;

  /// Whether the pod stops delivery when this alert is not acknowledged.
  final bool autoOff;

  final PodBeep beep;
  final PodBeepRepetition repetition;

  Uint8List get encoded => Uint8List.fromList([
        (type.bit << 4) |
            (enabled ? 1 << 3 : 0) |
            (trigger.onReservoir ? 1 << 2 : 0) |
            (autoOff ? 1 << 1 : 0) |
            ((durationMinutes >> 8) & 0x01),
        durationMinutes & 0xFF,
        (trigger.value >> 8) & 0xFF,
        trigger.value & 0xFF,
        repetition.value,
        beep.value,
      ]);
}

/// Configures the pod's own alerts.
///
/// These are the pod's last line of defence and the only warning the user gets
/// while the phone is out of range: it beeps on its own for expiry, low
/// reservoir and an unfinished activation. Sending an empty configuration would
/// silence a pod that has no other way to raise an alarm, so it is refused.
class PodProgramAlertsCommand extends PodCommand {
  PodProgramAlertsCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    required this.configurations,
    super.multiCommand,
  });

  final int nonce;
  final List<PodAlertConfiguration> configurations;

  @override
  PodCommandType get type => PodCommandType.programAlerts;

  @override
  Uint8List get encoded {
    if (configurations.isEmpty) {
      throw ArgumentError('Refusing to send an empty alert configuration');
    }
    final bodyLength = configurations.length * 6 + 4;
    return appendCrc(joinParts([
      buildHeader(bodyLength + 2),
      [type.value, bodyLength],
      bigEndian32(nonce),
      for (final configuration in configurations) configuration.encoded,
    ]));
  }

  /// The alert set an activation programs: warn the user before the pod expires,
  /// again when expiry is imminent, and when the reservoir runs low.
  ///
  /// [expiryMinutes] is the pod's own reported lifetime rather than a constant,
  /// so a pod reporting a different one is warned about at the right time.
  static List<PodAlertConfiguration> lifecycleDefaults({
    required int expiryMinutes,
    int warnBeforeExpiryMinutes = 7 * 60,
    int imminentBeforeExpiryMinutes = 60,
    int lowReservoirMicroLitres = 200,
  }) {
    return [
      PodAlertConfiguration(
        type: PodAlert.expiration,
        trigger:
            PodAlertTrigger.afterMinutes(expiryMinutes - warnBeforeExpiryMinutes),
        durationMinutes: warnBeforeExpiryMinutes,
        repetition: PodBeepRepetition.everyHour,
      ),
      PodAlertConfiguration(
        type: PodAlert.expirationImminent,
        trigger: PodAlertTrigger.afterMinutes(
            expiryMinutes - imminentBeforeExpiryMinutes),
        repetition: PodBeepRepetition.onceOnly,
      ),
      PodAlertConfiguration(
        type: PodAlert.lowReservoir,
        trigger: PodAlertTrigger.belowReservoir(lowReservoirMicroLitres),
        repetition: PodBeepRepetition.onceEveryMinuteForThreeMinutes,
      ),
    ];
  }

  /// The alert that fires if a pod is filled but never finishes activating, so a
  /// half-activated pod does not sit on a table silently.
  static List<PodAlertConfiguration> unfinishedActivation() {
    return const [
      PodAlertConfiguration(
        type: PodAlert.expiration,
        trigger: PodAlertTrigger.afterMinutes(5),
        durationMinutes: 55,
        repetition: PodBeepRepetition.everyFifteenMinutes,
      ),
    ];
  }
}
