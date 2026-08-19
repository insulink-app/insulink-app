import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';

PodBasalDelivery flat(double rate) =>
    PodBasalDelivery(List<double>.filled(24, rate));

void main() {
  group('a flat schedule delivers its rate over time', () {
    test('one hour at 1 U/h is one unit', () {
      final units = flat(1.0).unitsBetween(
        DateTime(2026, 3, 1, 10, 0),
        DateTime(2026, 3, 1, 11, 0),
      );
      expect(units, closeTo(1.0, 1e-9));
    });

    test('fifteen minutes at 0.8 U/h is a quarter of that rate', () {
      final units = flat(0.8).unitsBetween(
        DateTime(2026, 3, 1, 10, 0),
        DateTime(2026, 3, 1, 10, 15),
      );
      expect(units, closeTo(0.2, 1e-9));
    });

    test('a whole day equals the schedule total', () {
      final schedule = flat(1.25);
      final units = schedule.unitsBetween(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
      );
      expect(units, closeTo(schedule.dailyUnits, 1e-9));
      expect(units, closeTo(30.0, 1e-9));
    });
  });

  group('a varying schedule is followed hour by hour', () {
    final varying = PodBasalDelivery([
      for (var hour = 0; hour < 24; hour++) hour == 6 ? 2.0 : 0.5,
    ]);

    test('a window inside the raised hour uses the raised rate', () {
      final units = varying.unitsBetween(
        DateTime(2026, 3, 1, 6, 0),
        DateTime(2026, 3, 1, 6, 30),
      );
      expect(units, closeTo(1.0, 1e-9));
    });

    test('a window straddling an hour boundary splits at it', () {
      final units = varying.unitsBetween(
        DateTime(2026, 3, 1, 5, 30),
        DateTime(2026, 3, 1, 6, 30),
      );
      expect(units, closeTo(0.25 + 1.0, 1e-9));
    });

    test('a window spanning several hours sums each of them', () {
      final units = varying.unitsBetween(
        DateTime(2026, 3, 1, 5, 0),
        DateTime(2026, 3, 1, 8, 0),
      );
      expect(units, closeTo(0.5 + 2.0 + 0.5, 1e-9));
    });
  });

  group('windows that cross midnight', () {
    test('a window over midnight uses both hours schedules', () {
      final schedule = PodBasalDelivery([
        for (var hour = 0; hour < 24; hour++) hour == 23 ? 3.0 : 1.0,
      ]);
      final units = schedule.unitsBetween(
        DateTime(2026, 3, 1, 23, 30),
        DateTime(2026, 3, 2, 0, 30),
      );
      expect(units, closeTo(1.5 + 0.5, 1e-9));
    });

    test('several days sum without drifting', () {
      final units = flat(1.0).unitsBetween(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 4),
      );
      expect(units, closeTo(72.0, 1e-9));
    });
  });

  group('a window that cannot deliver yields zero, never a negative', () {
    test('an empty window', () {
      final moment = DateTime(2026, 3, 1, 10, 0);
      expect(flat(1.0).unitsBetween(moment, moment), 0);
    });

    test('a reversed window', () {
      expect(
        flat(1.0).unitsBetween(
          DateTime(2026, 3, 1, 11, 0),
          DateTime(2026, 3, 1, 10, 0),
        ),
        0,
      );
    });

    test('a schedule that is not 24 hours long', () {
      final broken = PodBasalDelivery(List<double>.filled(12, 1.0));
      expect(
        broken.unitsBetween(
          DateTime(2026, 3, 1, 10, 0),
          DateTime(2026, 3, 1, 11, 0),
        ),
        0,
      );
    });

    test('a zero-rate hour contributes nothing', () {
      final schedule = PodBasalDelivery(List<double>.filled(24, 0));
      expect(
        schedule.unitsBetween(
          DateTime(2026, 3, 1, 10, 0),
          DateTime(2026, 3, 1, 11, 0),
        ),
        0,
      );
    });

    test('a non-finite or negative rate is treated as no delivery', () {
      final schedule = PodBasalDelivery([
        double.nan,
        -1.0,
        for (var hour = 2; hour < 24; hour++) 1.0,
      ]);
      expect(
        schedule.unitsBetween(DateTime(2026, 3, 1, 0, 0), DateTime(2026, 3, 1, 2, 0)),
        0,
      );
      expect(
        schedule.unitsBetween(DateTime(2026, 3, 1, 2, 0), DateTime(2026, 3, 1, 3, 0)),
        closeTo(1.0, 1e-9),
      );
    });
  });

  group('a poll-sized window, which is what the monitor records', () {
    test('fifteen minutes of a realistic schedule', () {
      final schedule = PodBasalDelivery([
        for (var hour = 0; hour < 24; hour++) hour < 6 ? 0.65 : 0.95,
      ]);
      final units = schedule.unitsBetween(
        DateTime(2026, 3, 1, 3, 0),
        DateTime(2026, 3, 1, 3, 15),
      );
      expect(units, closeTo(0.65 / 4, 1e-9));
    });
  });

  group('a temporary rate overrides the schedule for its stretch', () {
    final schedule = List<double>.filled(24, 1.0);
    final noon = DateTime(2026, 3, 1, 12, 0);

    PodBasalDelivery withTemp(double rate, {required Duration length}) =>
        PodBasalDelivery(
          schedule,
          temporary: PodTemporaryBasal(
            unitsPerHour: rate,
            start: noon,
            end: noon.add(length),
          ),
        );

    test('a raised rate is billed at the raised rate', () {
      final units = withTemp(2.0, length: const Duration(hours: 1))
          .unitsBetween(noon, noon.add(const Duration(hours: 1)));
      expect(units, closeTo(2.0, 1e-9));
    });

    /// The case a temp basal exists for: booking the schedule here would tell the
    /// model about insulin the pod deliberately did not deliver.
    test('a zero rate books nothing, not the schedule', () {
      final units = withTemp(0, length: const Duration(hours: 1))
          .unitsBetween(noon, noon.add(const Duration(hours: 1)));
      expect(units, 0);
    });

    test('the schedule resumes the moment the stretch ends', () {
      final units = withTemp(0, length: const Duration(hours: 1))
          .unitsBetween(noon, noon.add(const Duration(hours: 2)));
      expect(units, closeTo(1.0, 1e-9), reason: 'only the second hour counts');
    });

    test('a stretch starting mid-hour splits at its start', () {
      final delivery = PodBasalDelivery(
        schedule,
        temporary: PodTemporaryBasal(
          unitsPerHour: 0,
          start: noon.add(const Duration(minutes: 30)),
          end: noon.add(const Duration(minutes: 90)),
        ),
      );
      // 30 min scheduled, 60 min at zero, 30 min scheduled again.
      final units = delivery.unitsBetween(noon, noon.add(const Duration(hours: 2)));
      expect(units, closeTo(0.5 + 0.0 + 0.5, 1e-9));
    });

    test('a window entirely before the stretch is unaffected', () {
      final units = withTemp(0, length: const Duration(hours: 1))
          .unitsBetween(noon.subtract(const Duration(hours: 1)), noon);
      expect(units, closeTo(1.0, 1e-9));
    });

    test('a window entirely after the stretch is unaffected', () {
      final start = noon.add(const Duration(hours: 3));
      final units = withTemp(0, length: const Duration(hours: 1))
          .unitsBetween(start, start.add(const Duration(hours: 1)));
      expect(units, closeTo(1.0, 1e-9));
    });

    test('cancelling early shortens the stretch', () {
      final temp = PodTemporaryBasal(
        unitsPerHour: 0,
        start: noon,
        end: noon.add(const Duration(hours: 2)),
      ).endedAt(noon.add(const Duration(hours: 1)));
      final units = PodBasalDelivery(schedule, temporary: temp)
          .unitsBetween(noon, noon.add(const Duration(hours: 2)));
      expect(units, closeTo(1.0, 1e-9), reason: 'the second hour is scheduled again');
    });

    test('it survives being stored and read back', () {
      final temp = PodTemporaryBasal(
        unitsPerHour: 0.35,
        start: noon,
        end: noon.add(const Duration(minutes: 90)),
      );
      final restored = PodTemporaryBasal.fromJson(temp.toJson());
      expect(restored.unitsPerHour, temp.unitsPerHour);
      expect(restored.start, temp.start);
      expect(restored.end, temp.end);
    });

    test('the stretch end is exclusive', () {
      final temp = PodTemporaryBasal(
        unitsPerHour: 0,
        start: noon,
        end: noon.add(const Duration(hours: 1)),
      );
      expect(temp.covers(noon), isTrue);
      expect(temp.covers(noon.add(const Duration(minutes: 59))), isTrue);
      expect(temp.covers(noon.add(const Duration(hours: 1))), isFalse);
    });
  });
}
