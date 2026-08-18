import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_basal_command.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

String toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

PodBasalProgram flat(int hundredthsPerHour) => PodBasalProgram([
      PodBasalSegment(
          startSlot: 0, endSlot: 48, rateHundredthUnitsPerHour: hundredthsPerHour),
    ]);

void main() {
  const nonce = 1229869870;

  group('captured basal programs encode byte-exactly', () {
    test('a flat 3.00 U/h schedule', () {
      final command = PodProgramBasalCommand(
        uniqueId: 37879809,
        sequenceNumber: 10,
        nonce: nonce,
        program: flat(300),
        now: DateTime(2021, 2, 17, 14, 47, 43),
        reminder: const PodProgramReminder(atEnd: true),
      );
      expect(
        toHex(command.encoded),
        '0242000128241a12494e532e0005e81d1708000c'
        'f01ef01ef01e130e40001593004c4b403840005b8d80827c',
      );
    });

    test('a flat 0.05 U/h schedule, where the odd pulse has to alternate', () {
      final command = PodProgramBasalCommand(
        uniqueId: 4241,
        sequenceNumber: 12,
        nonce: nonce,
        program: flat(5),
        now: DateTime(2021, 1, 30, 23, 21, 46),
        reminder: const PodProgramReminder(),
      );
      expect(
        toHex(command.encoded),
        '0000109130241a12494e532e0000c52e0f700000'
        'f800f800f800130e0000000707fcad8000f015752a00033b',
      );
    });

    test('all 24 hourly segments at different rates', () {
      final segments = <PodBasalSegment>[];
      for (var hour = 0; hour < 24; hour++) {
        final rate = switch (hour) {
          21 => 110,
          22 => 120,
          23 => 135,
          _ => hour * 5,
        };
        segments.add(PodBasalSegment(
          startSlot: hour * 2,
          endSlot: (hour + 1) * 2,
          rateHundredthUnitsPerHour: rate,
        ));
      }
      final command = PodProgramBasalCommand(
        uniqueId: 5,
        sequenceNumber: 2,
        nonce: nonce,
        program: PodBasalProgram(segments),
        now: DateTime(2021, 9, 7, 11, 9, 6),
        reminder: const PodProgramReminder(atEnd: true),
      );
      expect(
        toHex(command.encoded),
        '0000000508c41a28494e532e00018b16273000032000300130023003300430053006300730083009'
        '200a100b100c180d1398400b005e009e22e80002eb49d200000a15752a0000140aba9500001e0727'
        '0e000028055d4a800032044aa200003c0393870000460310bcdb005002aea540005a02625a000064'
        '02255100006e01f360e8007801c9c380008201a68d13008c01885e6d0096016e360000a0015752a0'
        '00aa0143209600b401312d0000be01211d2800c80112a88000dc00f9b07400f000e4e1c0010e00cb'
        '73558158',
      );
    });
  });

  group('PodBasalProgram slot mapping', () {
    test('an even hourly pulse count splits evenly', () {
      expect(flat(300).pulsesPerSlot.take(4), [30, 30, 30, 30]);
    });

    test('an odd hourly pulse count alternates the extra pulse', () {
      // 0.05 U/h = 1 pulse/h, so slots alternate 0 and 1.
      expect(flat(5).pulsesPerSlot.take(6), [0, 1, 0, 1, 0, 1]);
    });

    test('tenth-pulses carry the half pulse without alternating', () {
      expect(flat(5).tenthPulsesPerSlot.take(4), [5, 5, 5, 5]);
    });

    test('daily total matches the schedule', () {
      expect(flat(300).totalDailyUnits, closeTo(72.0, 1e-9));
      expect(flat(5).totalDailyUnits, closeTo(1.2, 1e-9));
    });

    test('the current slot tracks wall-clock time', () {
      final slot = flat(300).currentSlotAt(DateTime(2021, 2, 17, 14, 47, 43));
      expect(slot.index, 29);
      expect(slot.eighthSecondsRemaining, 5896);
      expect(slot.pulsesRemaining, 12);
    });

    test('rateAt reads the segment covering the time', () {
      final program = PodBasalProgram([
        const PodBasalSegment(startSlot: 0, endSlot: 12, rateHundredthUnitsPerHour: 80),
        const PodBasalSegment(startSlot: 12, endSlot: 48, rateHundredthUnitsPerHour: 120),
      ]);
      expect(program.rateAt(DateTime(2026, 1, 1, 2, 0)), closeTo(0.8, 1e-9));
      expect(program.rateAt(DateTime(2026, 1, 1, 9, 0)), closeTo(1.2, 1e-9));
    });
  });

  group('PodBasalProgram rejects schedules the pod cannot hold', () {
    test('a gap in coverage', () {
      expect(
        () => PodBasalProgram([
          const PodBasalSegment(startSlot: 0, endSlot: 12, rateHundredthUnitsPerHour: 80),
          const PodBasalSegment(startSlot: 20, endSlot: 48, rateHundredthUnitsPerHour: 80),
        ]),
        throwsA(isA<PodBasalProgramException>()),
      );
    });

    test('a short day', () {
      expect(
        () => PodBasalProgram([
          const PodBasalSegment(startSlot: 0, endSlot: 40, rateHundredthUnitsPerHour: 80),
        ]),
        throwsA(isA<PodBasalProgramException>()),
      );
    });

    test('an empty program', () {
      expect(() => PodBasalProgram([]), throwsA(isA<PodBasalProgramException>()));
    });

    test('a negative rate', () {
      expect(
        () => PodBasalProgram([
          const PodBasalSegment(startSlot: 0, endSlot: 48, rateHundredthUnitsPerHour: -5),
        ]),
        throwsA(isA<PodBasalProgramException>()),
      );
    });

    test('a rate finer than the pod can hold', () {
      expect(
        () => PodBasalSegment.fromHours(startHour: 0, endHour: 24, unitsPerHour: 0.855),
        throwsA(isA<PodBasalProgramException>()),
      );
    });
  });
}
