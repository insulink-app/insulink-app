import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_stop_delivery_command.dart';

String toHex(Uint8List bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join();

void main() {
  const nonce = 1229869870;

  group('control commands match captured frames', () {
    test('get status', () {
      final command = PodGetStatusCommand(uniqueId: 37879810, sequenceNumber: 15);
      expect(toHex(command.encoded), '024200023C030E0100024C');
    });

    test('get version', () {
      expect(toHex(PodGetVersionCommand(sequenceNumber: 0).encoded),
          'FFFFFFFF00060704FFFFFFFF82B2');
    });

    test('set unique id', () {
      final command = PodSetUniqueIdCommand(
        uniqueId: 37879811,
        sequenceNumber: 6,
        lotNumber: 135556289,
        podSequenceNumber: 681767,
        activatedAt: DateTime(2021, 2, 10, 14, 41),
      );
      expect(toHex(command.encoded),
          'FFFFFFFF18150313024200031404020A150E2908146CC1000A67278344');
    });

    test('deactivate', () {
      final command =
          PodDeactivateCommand(uniqueId: 37879809, sequenceNumber: 5, nonce: nonce);
      expect(toHex(command.encoded), '0242000114061C04494E532E001C');
    });

    test('silence alerts', () {
      final command = PodSilenceAlertsCommand(
        uniqueId: 37879811,
        sequenceNumber: 1,
        nonce: nonce,
        alerts: {PodAlert.lowReservoir},
      );
      expect(toHex(command.encoded), '0242000304071105494E532E1081CE');
    });
  });

  group('stop delivery', () {
    test('cancels a temp basal', () {
      final command = PodStopDeliveryCommand(
        uniqueId: 37879811,
        sequenceNumber: 0,
        nonce: nonce,
        target: PodDeliveryTarget.tempBasal,
      );
      expect(toHex(command.encoded), '0242000300071F05494E532E6201B1');
    });

    test('suspends everything', () {
      final command = PodStopDeliveryCommand(
        uniqueId: 37879811,
        sequenceNumber: 2,
        nonce: nonce,
        target: PodDeliveryTarget.all,
        beep: PodBeep.silent,
      );
      expect(toHex(command.encoded), '0242000308071F05494E532E078287');
    });

    test('the emergency stop targets every delivery stream', () {
      final command = PodStopDeliveryCommand.suspendAll(
          uniqueId: 37879811, sequenceNumber: 2, nonce: nonce);
      expect(command.target, PodDeliveryTarget.all);
      expect(command.beep, PodBeep.longSingleBeep);
    });
  });

  group('bolus', () {
    test('matches the captured 5 U frame', () {
      final command = PodProgramBolusCommand(
        uniqueId: 37879809,
        sequenceNumber: 14,
        nonce: nonce,
        amount: PodBolusAmount.fromUnits(5.0),
        reminder: const PodProgramReminder(atEnd: true),
      );
      expect(
        toHex(command.encoded),
        '02420001381F1A0E494E532E02010F01064000640064'
        '170D4003E800030D4000000000000080F6',
      );
    });

    test('converts units to pulses on the 0.05 U grid', () {
      expect(PodBolusAmount.fromUnits(0.05).pulses, 1);
      expect(PodBolusAmount.fromUnits(1.0).pulses, 20);
      expect(PodBolusAmount.fromUnits(4.35).pulses, 87);
      expect(PodBolusAmount.fromUnits(30.0).pulses, 600);
    });

    test('every valid dose round-trips units to pulses and back', () {
      for (var pulses = 1; pulses <= PodBolusAmount.maxPulses; pulses++) {
        final amount = PodBolusAmount.fromUnits(pulses * PodBolusAmount.pulseUnits);
        expect(amount.pulses, pulses, reason: 'at $pulses pulses');
      }
    });

    test('refuses a dose off the pulse grid instead of rounding it', () {
      expect(() => PodBolusAmount.fromUnits(1.03), throwsA(isA<PodDoseException>()));
      expect(() => PodBolusAmount.fromUnits(0.01), throwsA(isA<PodDoseException>()));
    });

    test('refuses zero, negative and non-finite doses', () {
      expect(() => PodBolusAmount.fromUnits(0), throwsA(isA<PodDoseException>()));
      expect(() => PodBolusAmount.fromUnits(-1.0), throwsA(isA<PodDoseException>()));
      expect(() => PodBolusAmount.fromUnits(double.nan), throwsA(isA<PodDoseException>()));
      expect(
          () => PodBolusAmount.fromUnits(double.infinity), throwsA(isA<PodDoseException>()));
    });

    test('refuses a dose above the pod maximum', () {
      expect(() => PodBolusAmount.fromUnits(30.05), throwsA(isA<PodDoseException>()));
      expect(() => PodBolusAmount.fromPulses(601), throwsA(isA<PodDoseException>()));
    });

    test('the encoded frame always carries the requested pulse count', () {
      for (final units in <double>[0.05, 0.5, 1.0, 4.35, 12.7, 30.0]) {
        final amount = PodBolusAmount.fromUnits(units);
        final frame = PodProgramBolusCommand(
          uniqueId: 37879809,
          sequenceNumber: 3,
          nonce: nonce,
          amount: amount,
        ).encoded;
        final view = ByteData.view(frame.buffer, frame.offsetInBytes);
        expect(view.getUint16(18), amount.pulses, reason: 'interlock at $units U');
        expect(view.getUint16(20), amount.pulses, reason: 'element at $units U');
        expect(view.getUint16(25), amount.pulses * 10, reason: 'tenths at $units U');
      }
    });
  });
}
