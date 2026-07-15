import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';

Meal bolusAt(DateTime time, double bolus) => Meal(
  time: time,
  carbs: 0,
  glucoseMgdl: 120,
  bolus: bolus,
  entries: const [],
);

void main() {
  const iob = ActiveInsulin(Duration(hours: 3));
  final now = DateTime(2026, 7, 15, 12);

  test('a fresh bolus is fully active', () {
    expect(iob.units([bolusAt(now, 6)], now: now), closeTo(6, 0.001));
  });

  test('decays linearly over the duration', () {
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    expect(iob.units([bolusAt(oneHourAgo, 6)], now: now), closeTo(4, 0.001));
  });

  test('a dose past the duration is gone', () {
    final old = now.subtract(const Duration(hours: 3, minutes: 1));
    expect(iob.units([bolusAt(old, 6)], now: now), 0);
  });

  test('sums the still-active doses only', () {
    final meals = [
      bolusAt(now.subtract(const Duration(hours: 5)), 10),
      bolusAt(now.subtract(const Duration(minutes: 90)), 4),
      bolusAt(now, 2),
    ];
    expect(iob.units(meals, now: now), closeTo(4, 0.001));
  });

  test('a future-dated bolus never exceeds its dose', () {
    final ahead = now.add(const Duration(hours: 2));
    expect(iob.units([bolusAt(ahead, 5)], now: now), closeTo(5, 0.001));
  });

  test('the configured duration drives the decay rate', () {
    const slow = ActiveInsulin(Duration(hours: 6));
    final threeHoursAgo = now.subtract(const Duration(hours: 3));
    expect(
      slow.units([bolusAt(threeHoursAgo, 8)], now: now),
      closeTo(4, 0.001),
    );
  });

  test('activeUntil is the newest active dose wearing off', () {
    final meals = [
      bolusAt(now.subtract(const Duration(hours: 2)), 3),
      bolusAt(now.subtract(const Duration(minutes: 30)), 3),
    ];
    expect(
      iob.activeUntil(meals, now: now),
      now.add(const Duration(hours: 2, minutes: 30)),
    );
  });

  test('activeUntil is null while nothing is active', () {
    final old = bolusAt(now.subtract(const Duration(hours: 4)), 3);
    expect(iob.activeUntil([old], now: now), isNull);
  });
}
