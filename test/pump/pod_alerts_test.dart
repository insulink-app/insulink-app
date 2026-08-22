import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_alerts_command.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

String toHex(Uint8List bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join();

void main() {
  const nonce = 1229869870;

  test('captured expiration alert pair', () {
    final command = PodProgramAlertsCommand(
      uniqueId: 37879811,
      sequenceNumber: 3,
      nonce: nonce,
      multiCommand: true,
      configurations: const [
        PodAlertConfiguration(
          type: PodAlert.expiration,
          trigger: PodAlertTrigger.afterMinutes(4305),
          durationMinutes: 420,
          repetition: PodBeepRepetition.everyHour,
        ),
        PodAlertConfiguration(
          type: PodAlert.expirationImminent,
          trigger: PodAlertTrigger.afterMinutes(4725),
          repetition: PodBeepRepetition.onceOnly,
        ),
      ],
    );
    expect(toHex(command.encoded),
        '024200038C121910494E532E79A410D1050228001275060280F5');
  });

  test('captured low reservoir alert', () {
    final command = PodProgramAlertsCommand(
      uniqueId: 37879811,
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
    expect(toHex(command.encoded), '02420003200C190A494E532E4C0000C801020149');
  });

  test('captured user expiration alert', () {
    final command = PodProgramAlertsCommand(
      uniqueId: 37879811,
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
    expect(toHex(command.encoded), '024200033C0C190A494E532E38000FEF030203E2');
  });

  test('captured unfinished-activation alert', () {
    final command = PodProgramAlertsCommand(
      uniqueId: 37879811,
      sequenceNumber: 10,
      nonce: nonce,
      configurations: PodProgramAlertsCommand.unfinishedActivation(),
    );
    expect(toHex(command.encoded), '02420003280C190A494E532E7837000508020356');
  });

  test('the lifecycle defaults cover expiry, imminent expiry and reservoir', () {
    final defaults =
        PodProgramAlertsCommand.lifecycleDefaults(expiryMinutes: 80 * 60);
    expect(defaults.map((entry) => entry.type), [
      PodAlert.expiration,
      PodAlert.expirationImminent,
      PodAlert.lowReservoir,
    ]);
    expect(defaults[0].trigger.value, 80 * 60 - 7 * 60);
    expect(defaults[1].trigger.value, 80 * 60 - 60);
    expect(defaults[2].trigger.onReservoir, isTrue);
  });

  test('an empty alert configuration is refused', () {
    final command = PodProgramAlertsCommand(
      uniqueId: 37879811,
      sequenceNumber: 1,
      nonce: nonce,
      configurations: const [],
    );
    expect(() => command.encoded, throwsArgumentError);
  });

  /// The pod's own alerting is the last warning a user gets while the phone is
  /// out of range. The packed fields silently wrap a value that does not fit, so
  /// a wrong number becomes a wrong warning with nothing anywhere saying so.
  group('a value the wire fields cannot carry is refused', () {
    PodAlertConfiguration configuration({int duration = 0, int after = 60}) =>
        PodAlertConfiguration(
          type: PodAlert.expiration,
          trigger: PodAlertTrigger.afterMinutes(after),
          durationMinutes: duration,
        );

    test('a duration past the 9-bit field throws', () {
      expect(
        () => configuration(duration: 512).encoded,
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the widest duration that fits still encodes', () {
      expect(configuration(duration: 511).encoded, hasLength(6));
    });

    /// The one that was reachable: a pod reporting a life shorter than the
    /// warning turned the subtraction negative, and -120 encodes as 65416.
    test('a negative trigger throws', () {
      expect(
        () => configuration(after: -120).encoded,
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a trigger past the 16-bit field throws', () {
      expect(
        () => configuration(after: 65536).encoded,
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  /// A pod claiming a life shorter than the warning window is already inside it,
  /// so it is warned about at once rather than at a negative time.
  group('a short-lived pod still gets usable alerts', () {
    test('the trigger never goes negative', () {
      final alerts = PodProgramAlertsCommand.lifecycleDefaults(
        expiryMinutes: 300,
      );

      for (final alert in alerts) {
        expect(alert.trigger.value, greaterThanOrEqualTo(0));
        expect(() => alert.encoded, returnsNormally);
      }
    });

    test('an ordinary pod is unchanged', () {
      final alerts = PodProgramAlertsCommand.lifecycleDefaults(
        expiryMinutes: 80 * 60,
      );

      expect(alerts.first.trigger.value, 80 * 60 - 7 * 60);
    });
  });
}
