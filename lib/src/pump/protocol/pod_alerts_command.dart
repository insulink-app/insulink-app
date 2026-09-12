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

  /// The widest [durationMinutes] the 9-bit field can carry.
  static const int maxDurationMinutes = 0x1FF;

  /// The widest [PodAlertTrigger.value] the 16-bit field can carry.
  static const int maxTriggerValue = 0xFFFF;

  Uint8List get encoded {
    _refuseWhatTheFieldsCannotCarry();
    return Uint8List.fromList([
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

  /// Throws rather than encoding a value the fields cannot hold.
  ///
  /// The masks below do not protect anything: they are what MAKES a bad value
  /// silent. A trigger of -120 minutes encodes as `(-120 >> 8) & 0xFF` = 255 and
  /// `-120 & 0xFF` = 136, so the pod is told to alert after 65416 minutes and
  /// nothing anywhere says so. A duration past 511 wraps the same way.
  ///
  /// This is a pod's own alerting being configured, which is the last warning a
  /// user gets while the phone is out of range, and a wrong one either goes off
  /// when it should not or fails to go off when it should. The bolus command
  /// already refuses a frame that disagrees with itself for the same reason;
  /// this is the same rule applied to the other command that carries packed
  /// numbers.
  void _refuseWhatTheFieldsCannotCarry() {
    if (durationMinutes < 0 || durationMinutes > maxDurationMinutes) {
      throw ArgumentError.value(
        durationMinutes,
        'durationMinutes',
        'Outside the 9-bit field for a ${type.name} alert',
      );
    }
    if (trigger.value < 0 || trigger.value > maxTriggerValue) {
      throw ArgumentError.value(
        trigger.value,
        'trigger',
        'Outside the 16-bit field for a ${type.name} alert',
      );
    }
  }
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
    return appendCrc(
      joinParts([
        buildHeader(bodyLength + 2),
        [type.value, bodyLength],
        bigEndian32(nonce),
        for (final configuration in configurations) configuration.encoded,
      ]),
    );
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
    final warnAfter = _minutesInto(expiryMinutes, warnBeforeExpiryMinutes);
    final imminentAfter = _minutesInto(
      expiryMinutes,
      imminentBeforeExpiryMinutes,
    );
    return [
      PodAlertConfiguration(
        type: PodAlert.expiration,
        trigger: PodAlertTrigger.afterMinutes(warnAfter),
        // Never past the point it is warning about, and never past the field:
        // an alert that outlasts the pod would keep sounding after there is
        // nothing left to warn about.
        durationMinutes: warnBeforeExpiryMinutes.clamp(
          0,
          PodAlertConfiguration.maxDurationMinutes,
        ),
        repetition: PodBeepRepetition.everyHour,
      ),
      PodAlertConfiguration(
        type: PodAlert.expirationImminent,
        trigger: PodAlertTrigger.afterMinutes(imminentAfter),
        repetition: PodBeepRepetition.onceOnly,
      ),
      PodAlertConfiguration(
        type: PodAlert.lowReservoir,
        trigger: PodAlertTrigger.belowReservoir(lowReservoirMicroLitres),
        repetition: PodBeepRepetition.onceEveryMinuteForThreeMinutes,
      ),
    ];
  }

  /// How far into the pod's life an alert with [beforeExpiryMinutes] of warning
  /// should fire.
  ///
  /// Never negative. The lifetime is what the POD reported, not a constant, so a
  /// pod claiming a life shorter than the warning turns the subtraction negative,
  /// and a negative trigger encodes as tens of thousands of minutes rather than
  /// as an error. Such a pod is warned about immediately instead, which is the
  /// only honest answer: it is already inside its own warning window.
  static int _minutesInto(int expiryMinutes, int beforeExpiryMinutes) {
    final into = expiryMinutes - beforeExpiryMinutes;
    return into < 0 ? 0 : into;
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
