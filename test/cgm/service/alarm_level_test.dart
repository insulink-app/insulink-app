import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
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

  group('G7AlarmManager.advisoryLevelFor', () {
    const t = (low: 70, high: 180);

    test('in range with a forecast that stays in range → none', () {
      expect(
        G7AlarmManager.advisoryLevelFor(120, (low: 90, high: 150), t),
        AdvisoryLevel.none,
      );
    });

    test('in range but forecast dips to/below low → low', () {
      expect(
        G7AlarmManager.advisoryLevelFor(120, (low: 65, high: 120), t),
        AdvisoryLevel.low,
      );
    });

    test('in range but forecast climbs to/above high → high', () {
      expect(
        G7AlarmManager.advisoryLevelFor(150, (low: 150, high: 190), t),
        AdvisoryLevel.high,
      );
    });

    test('already out of range → none (the real alarm owns it)', () {
      // Current already low: advisory suppressed even with a low forecast.
      expect(
        G7AlarmManager.advisoryLevelFor(68, (low: 50, high: 68), t),
        AdvisoryLevel.none,
      );
      // Current already high.
      expect(
        G7AlarmManager.advisoryLevelFor(185, (low: 185, high: 220), t),
        AdvisoryLevel.none,
      );
    });

    test('low takes precedence when the forecast crosses both bounds', () {
      expect(
        G7AlarmManager.advisoryLevelFor(120, (low: 60, high: 200), t),
        AdvisoryLevel.low,
      );
    });
  });
}
