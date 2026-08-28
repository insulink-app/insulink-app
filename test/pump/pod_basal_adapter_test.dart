import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
import 'package:insulink/src/pump/protocol/pod_basal_program.dart';

BasalProfile profileWith(List<double> rates) => BasalProfile(
      name: 'test',
      rates: List<double>.of(rates),
      peaks: const [],
      dailyTotal: rates.fold<double>(0, (sum, rate) => sum + rate),
    );

BasalProfile flat(double rate) =>
    profileWith(List<double>.filled(24, rate));

void main() {
  group('an hourly profile becomes half-hour pod slots', () {
    test('a flat profile covers the whole day', () {
      final program = PodBasalAdapter(flat(0.8)).program;
      expect(program.segments, hasLength(24));
      expect(program.segments.first.startSlot, 0);
      expect(program.segments.last.endSlot, PodBasalProgram.slotsPerDay);
      expect(program.totalDailyUnits, closeTo(19.2, 1e-9));
    });

    test('each hour becomes two identical slots, with no interpolation', () {
      final rates = List<double>.filled(24, 0.5)
        ..[6] = 1.5
        ..[7] = 0.75;
      final program = PodBasalAdapter(profileWith(rates)).program;
      expect(program.rateAt(DateTime(2026, 1, 1, 6, 0)), closeTo(1.5, 1e-9));
      expect(program.rateAt(DateTime(2026, 1, 1, 6, 30)), closeTo(1.5, 1e-9));
      expect(program.rateAt(DateTime(2026, 1, 1, 7, 0)), closeTo(0.75, 1e-9));
      expect(program.rateAt(DateTime(2026, 1, 1, 7, 30)), closeTo(0.75, 1e-9));
      expect(program.rateAt(DateTime(2026, 1, 1, 8, 0)), closeTo(0.5, 1e-9));
    });

    test('the pod schedule delivers the profile total', () {
      final rates = List<double>.generate(24, (hour) => (hour % 4) * 0.05);
      final profile = profileWith(rates);
      final program = PodBasalAdapter(profile).program;
      final expected = rates.fold<double>(0, (sum, rate) => sum + rate);
      expect(program.totalDailyUnits, closeTo(expected, 1e-9));
    });

    test('a zero hour is kept as a real zero, not smoothed away', () {
      final rates = List<double>.filled(24, 1.0)..[3] = 0;
      final program = PodBasalAdapter(profileWith(rates)).program;
      expect(program.rateAt(DateTime(2026, 1, 1, 3, 30)), 0);
      expect(program.hasZeroSegments, isTrue);
    });

    test('every rate the app can produce converts', () {
      for (var step = 0; step <= BasalProfile.maxRate / BasalProfile.step; step++) {
        final rate = step * BasalProfile.step;
        final adapter = PodBasalAdapter(flat(rate));
        expect(adapter.isProgrammable, isTrue, reason: '$rate U/h');
      }
    });
  });

  group('a profile the pod cannot hold is refused, not rounded', () {
    test('a rate finer than the pod step', () {
      final adapter = PodBasalAdapter(flat(0.53));
      expect(adapter.isProgrammable, isFalse);
      expect(adapter.problem, contains('multiple of'));
      expect(() => adapter.program, throwsA(isA<PodBasalProgramException>()));
    });

    test('a rate above the pod maximum', () {
      expect(PodBasalAdapter(flat(35.0)).isProgrammable, isFalse);
    });

    test('a negative or non-finite rate', () {
      expect(PodBasalAdapter(flat(-0.5)).isProgrammable, isFalse);
      expect(PodBasalAdapter(flat(double.nan)).isProgrammable, isFalse);
    });

    test('a profile that does not cover 24 hours', () {
      final adapter = PodBasalAdapter(profileWith(List<double>.filled(12, 1.0)));
      expect(adapter.isProgrammable, isFalse);
      expect(adapter.problem, contains('24 hours'));
    });

    test('a programmable profile reports no problem', () {
      expect(PodBasalAdapter(flat(1.0)).problem, isNull);
    });
  });

  group('the profile editor and the pod agree on the step', () {
    /// If these ever diverge, a profile the editor happily produces would be
    /// rejected at programming time — so they are pinned together here.
    test('the app snaps to the step the pod meters in', () {
      expect(BasalProfile.step, 0.05);
      final snapped = flat(0.5)..setHour(0, 0.53);
      expect(PodBasalAdapter(snapped).isProgrammable, isTrue);
    });
  });
}
