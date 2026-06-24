import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/g7/service/alarms.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

typedef Thresholds = ({
  GlucoseUnit unit,
  int urgentLow,
  int low,
  int high,
  int urgentHigh,
});

const Thresholds standard = (
  unit: GlucoseUnit.mgdl,
  urgentLow: 55,
  low: 70,
  high: 180,
  urgentHigh: 250,
);

void main() {
  group('G7AlarmManager.levelFor', () {
    test('in-range readings raise no alarm', () {
      expect(G7AlarmManager.levelFor(100, standard), G7AlarmLevel.none);
      expect(G7AlarmManager.levelFor(71, standard), G7AlarmLevel.none);
      expect(G7AlarmManager.levelFor(179, standard), G7AlarmLevel.none);
    });

    test('low warning between urgentLow and low (inclusive of low)', () {
      expect(G7AlarmManager.levelFor(70, standard), G7AlarmLevel.lowWarning);
      expect(G7AlarmManager.levelFor(60, standard), G7AlarmLevel.lowWarning);
    });

    test('urgent low at or below urgentLow', () {
      expect(G7AlarmManager.levelFor(55, standard), G7AlarmLevel.lowUrgent);
      expect(G7AlarmManager.levelFor(40, standard), G7AlarmLevel.lowUrgent);
    });

    test('high warning between high and urgentHigh (inclusive of high)', () {
      expect(G7AlarmManager.levelFor(180, standard), G7AlarmLevel.highWarning);
      expect(G7AlarmManager.levelFor(220, standard), G7AlarmLevel.highWarning);
    });

    test('urgent high at or above urgentHigh', () {
      expect(G7AlarmManager.levelFor(250, standard), G7AlarmLevel.highUrgent);
      expect(G7AlarmManager.levelFor(400, standard), G7AlarmLevel.highUrgent);
    });

    test('urgent takes precedence over warning at the boundaries', () {
      // urgentLow == low would still classify as urgent (checked first).
      const collapsed = (
        unit: GlucoseUnit.mgdl,
        urgentLow: 70,
        low: 70,
        high: 180,
        urgentHigh: 180,
      );
      expect(G7AlarmManager.levelFor(70, collapsed), G7AlarmLevel.lowUrgent);
      expect(G7AlarmManager.levelFor(180, collapsed), G7AlarmLevel.highUrgent);
    });
  });
}
