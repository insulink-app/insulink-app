import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_temp_basal_command.dart';

String toHex(Uint8List bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join();

void main() {
  const nonce = 1229869870;

  PodProgramTempBasalCommand command({
    required double unitsPerHour,
    required int minutes,
    required int sequenceNumber,
    required PodProgramReminder reminder,
    int uniqueId = 37879809,
  }) {
    return PodProgramTempBasalCommand(
      uniqueId: uniqueId,
      sequenceNumber: sequenceNumber,
      nonce: nonce,
      rate: PodTempBasalRate(unitsPerHour: unitsPerHour, minutes: minutes),
      reminder: reminder,
    );
  }

  group('captured temp basals encode byte-exactly', () {
    test('5.05 U/h for 60 min, where the odd pulse alternates', () {
      expect(
        toHex(command(
          unitsPerHour: 5.05,
          minutes: 60,
          sequenceNumber: 15,
          reminder: const PodProgramReminder(atEnd: true),
        ).encoded),
        '024200013C201A0E494E532E01011102384000321832'
        '160E400003F20036634403F20036634482A6',
      );
    });

    test('0 U/h for 300 min, delivered as the pod trickle', () {
      expect(
        toHex(command(
          unitsPerHour: 0,
          minutes: 300,
          sequenceNumber: 7,
          reminder: const PodProgramReminder(atStart: true, atEnd: true),
        ).encoded),
        '024200011C201A0E494E532E0100820A384000009000'
        '160EC000000A6B49D200000A6B49D20001E3',
      );
    });

    test('0 U/h for 30 min, a genuine zero', () {
      expect(
        toHex(command(
          unitsPerHour: 0,
          minutes: 30,
          sequenceNumber: 7,
          reminder: const PodProgramReminder(atStart: true, atEnd: true),
        ).encoded),
        '024200011C201A0E494E532E010079013840000000'
        '00160EC00000016B49D2000001EB49D200815B',
      );
    });

    test('0 U/h for 720 min, the longest the pod takes', () {
      expect(
        toHex(command(
          unitsPerHour: 0,
          minutes: 720,
          sequenceNumber: 7,
          reminder: const PodProgramReminder(atStart: true, atEnd: true),
        ).encoded),
        '024200011C221A10494E532E0100901838400000F0007000'
        '160EC00000186B49D20000186B49D2000132',
      );
    });
  });

  group('PodTempBasalRate', () {
    test('converts a rate to alternating pulses per slot', () {
      final rate = PodTempBasalRate(unitsPerHour: 5.05, minutes: 60);
      expect(rate.pulsesPerHour, 101);
      expect(rate.pulsesPerSlot, [50, 51]);
      expect(rate.tenthPulsesPerSlot, [505, 505]);
    });

    test('substitutes a trickle for a long zero, and says so', () {
      final long = PodTempBasalRate(unitsPerHour: 0, minutes: 300);
      expect(long.isTrickleSubstituted, isTrue);
      expect(long.tenthPulsesPerSlot.first, 1);

      final short = PodTempBasalRate(unitsPerHour: 0, minutes: 120);
      expect(short.isTrickleSubstituted, isFalse);
      expect(short.tenthPulsesPerSlot.first, 0);
    });

    test('refuses a duration that is not whole 30-minute slots', () {
      expect(() => PodTempBasalRate(unitsPerHour: 1.0, minutes: 45),
          throwsA(isA<PodBasalProgramException>()));
      expect(() => PodTempBasalRate(unitsPerHour: 1.0, minutes: 0),
          throwsA(isA<PodBasalProgramException>()));
    });

    test('refuses a duration beyond twelve hours', () {
      expect(() => PodTempBasalRate(unitsPerHour: 1.0, minutes: 750),
          throwsA(isA<PodBasalProgramException>()));
      expect(PodTempBasalRate(unitsPerHour: 1.0, minutes: 720).slots, 24);
    });

    test('refuses a rate above the pod maximum or below zero', () {
      expect(() => PodTempBasalRate(unitsPerHour: 30.5, minutes: 30),
          throwsA(isA<PodBasalProgramException>()));
      expect(() => PodTempBasalRate(unitsPerHour: -1.0, minutes: 30),
          throwsA(isA<PodBasalProgramException>()));
      expect(() => PodTempBasalRate(unitsPerHour: double.nan, minutes: 30),
          throwsA(isA<PodBasalProgramException>()));
    });
  });
}
