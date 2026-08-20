import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_alerts_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// The four alert vectors from the reference driver's own test suite
/// (`ProgramAlertsCommandTest.kt`), byte for byte.
///
/// The pod rejected our alert programming with a NAK code that is not even in
/// the reference's error list, which meant the payload was wrong somewhere and
/// nothing local could say where. These are the only vectors in existence for
/// this command, so they are the contract.
void main() {
  String hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  const uniqueId = 37879811;
  const nonce = 1229869870;

  test('the published expiration alert pair', () {
    final command = PodProgramAlertsCommand(
      uniqueId: uniqueId,
      sequenceNumber: 3,
      nonce: nonce,
      multiCommand: true,
      configurations: const [
        PodAlertConfiguration(
          type: PodAlert.expiration,
          durationMinutes: 420,
          trigger: PodAlertTrigger.afterMinutes(4305),
          repetition: PodBeepRepetition.everyHour,
        ),
        PodAlertConfiguration(
          type: PodAlert.expirationImminent,
          trigger: PodAlertTrigger.afterMinutes(4725),
          repetition: PodBeepRepetition.onceOnly,
        ),
      ],
    );

    expect(hex(command.encoded),
        '024200038c121910494e532e79a410d1050228001275060280f5');
  });

  test('the low-reservoir alert', () {
    final command = PodProgramAlertsCommand(
      uniqueId: uniqueId,
      sequenceNumber: 8,
      nonce: nonce,
      configurations: const [
        PodAlertConfiguration(
          type: PodAlert.lowReservoir,
          trigger: PodAlertTrigger.belowReservoir(200),
          repetition: PodBeepRepetition.onceEveryMinuteForThreeMinutes,
        ),
      ],
    );

    expect(hex(command.encoded), '02420003200c190a494e532e4c0000c801020149');
  });

  test('the user-set expiration alert', () {
    final command = PodProgramAlertsCommand(
      uniqueId: uniqueId,
      sequenceNumber: 15,
      nonce: nonce,
      configurations: const [
        PodAlertConfiguration(
          type: PodAlert.userSetExpiration,
          trigger: PodAlertTrigger.afterMinutes(4079),
          repetition: PodBeepRepetition.everyMinuteAndEveryFifteen,
        ),
      ],
    );

    expect(hex(command.encoded), '024200033c0c190a494e532e38000fef030203e2');
  });

  /// The unfinished-activation alert, which is the one that failed on hardware.
  test('the lump-of-coal alert', () {
    final command = PodProgramAlertsCommand(
      uniqueId: uniqueId,
      sequenceNumber: 10,
      nonce: nonce,
      configurations: const [
        PodAlertConfiguration(
          type: PodAlert.expiration,
          durationMinutes: 55,
          trigger: PodAlertTrigger.afterMinutes(5),
          repetition: PodBeepRepetition.everyFifteenMinutes,
        ),
      ],
    );

    expect(hex(command.encoded), '02420003280c190a494e532e7837000508020356');
  });
}
