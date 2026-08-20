import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// Which status page to read. [defaultPage] carries delivery state, reservoir
/// and active alerts and is the one the app polls.
enum PodStatusPage {
  defaultPage(0x00),
  page1(0x01),
  alarmStatus(0x02),
  page3(0x03);

  const PodStatusPage(this.value);

  final int value;
}

/// Reads the pod's current state. Carries no nonce and changes nothing, so it
/// is safe to retry.
class PodGetStatusCommand extends PodCommand {
  PodGetStatusCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    this.page = PodStatusPage.defaultPage,
    super.multiCommand,
  });

  final PodStatusPage page;

  @override
  PodCommandType get type => PodCommandType.getStatus;

  @override
  Uint8List get encoded => appendCrc(joinParts([
        buildHeader(3),
        [type.value, 0x01, page.value],
      ]));
}

/// Reads firmware, lot and sequence number from a pod that has not been
/// assigned an id yet — the first command of an activation.
class PodGetVersionCommand extends PodCommand {
  PodGetVersionCommand({required super.sequenceNumber, super.multiCommand})
      : super(uniqueId: podUnassignedUniqueId);

  @override
  PodCommandType get type => PodCommandType.getVersion;

  @override
  Uint8List get encoded => appendCrc(joinParts([
        buildHeader(6),
        [type.value, 0x04],
        bigEndian32(uniqueId),
      ]));
}

/// Binds a pod to this controller.
///
/// After this succeeds the pod answers only to [uniqueId] and no other
/// controller — including the user's own PDM — can command it again. That is
/// irreversible for the life of the pod, so the UI must have told the user
/// before this is sent. See `docs/OMNIPOD.md`.
class PodSetUniqueIdCommand extends PodCommand {
  PodSetUniqueIdCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.lotNumber,
    required this.podSequenceNumber,
    required this.activatedAt,
    super.multiCommand,
  });

  final int lotNumber;
  final int podSequenceNumber;
  final DateTime activatedAt;

  @override
  PodCommandType get type => PodCommandType.setUniqueId;

  @override
  Uint8List get encoded => appendCrc(joinParts([
        buildHeader(21, addressedTo: podUnassignedUniqueId),
        [type.value, 0x13],
        bigEndian32(uniqueId),
        [0x14, 0x04],
        _encodedActivationTime,
        bigEndian32(lotNumber),
        bigEndian32(podSequenceNumber),
      ]));

  Uint8List get _encodedActivationTime => Uint8List.fromList([
        activatedAt.month,
        activatedAt.day,
        activatedAt.year % 100,
        activatedAt.hour,
        activatedAt.minute,
      ]);
}

/// Ends the pod's life: stops delivery and puts it into deactivated state so it
/// can be removed. Reachable even when the pod is alarming.
class PodDeactivateCommand extends PodCommand {
  PodDeactivateCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    super.multiCommand,
  });

  final int nonce;

  @override
  PodCommandType get type => PodCommandType.deactivate;

  @override
  Uint8List get encoded => appendCrc(joinParts([
        buildHeader(6),
        [type.value, 0x04],
        bigEndian32(nonce),
      ]));
}

/// Acknowledges pod alerts so it stops beeping. Does not change delivery.
class PodSilenceAlertsCommand extends PodCommand {
  PodSilenceAlertsCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    required this.nonce,
    required this.alerts,
    super.multiCommand,
  });

  final int nonce;
  final Set<PodAlert> alerts;

  @override
  PodCommandType get type => PodCommandType.silenceAlerts;

  @override
  Uint8List get encoded => appendCrc(joinParts([
        buildHeader(7),
        [type.value, 0x05],
        bigEndian32(nonce),
        [PodAlert.encode(alerts)],
      ]));
}

/// Sets the pod's reminder beeps, and optionally makes it beep right now.
///
/// The immediate beep is the only way to ask a pod to make a sound on demand: it
/// answers whether the pod is in earshot and whether its beeper still works,
/// which is worth knowing before relying on it for an occlusion at three in the
/// morning.
///
/// The three reminders are re-stated on every send, because the pod holds one set
/// and this command replaces all of it. Leaving one out silences it.
class PodProgramBeepsCommand extends PodCommand {
  PodProgramBeepsCommand({
    required super.uniqueId,
    required super.sequenceNumber,
    this.immediateBeep = PodBeep.fourTimesBipBeep,
    this.basalReminder = const PodProgramReminder(),
    this.tempBasalReminder = const PodProgramReminder(),
    this.bolusReminder = const PodProgramReminder(),
    super.multiCommand,
  });

  /// Sounded once, as soon as the pod takes the command.
  final PodBeep immediateBeep;

  final PodProgramReminder basalReminder;
  final PodProgramReminder tempBasalReminder;
  final PodProgramReminder bolusReminder;

  @override
  PodCommandType get type => PodCommandType.programBeeps;

  @override
  Uint8List get encoded => appendCrc(joinParts([
        buildHeader(6),
        [type.value, 0x04, immediateBeep.value],
        basalReminder.encoded,
        tempBasalReminder.encoded,
        bolusReminder.encoded,
      ]));
}
