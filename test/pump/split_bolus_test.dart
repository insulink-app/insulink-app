import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/injection/split_bolus_choice.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/split_bolus.dart';

import 'fake_secure_storage.dart';

void main() {
  final confirmedAt = DateTime(2026, 11, 9, 18);

  test('off, the whole dose goes out at once and nothing is planned', () {
    const choice = SplitBolusChoice();

    expect(choice.nowUnits(3.3), 3.3);
    expect(
      choice.plan(3.3, from: confirmedAt, glucoseMgdl: 120, mealKey: 1),
      isNull,
    );
  });

  test('a split gives its share now and spreads every pulse of the rest', () {
    const choice = SplitBolusChoice(
      enabled: true,
      nowPercent: 50,
      overMinutes: 60,
    );

    final plan = choice.plan(
      3.3,
      from: confirmedAt,
      glucoseMgdl: 120,
      mealKey: 1,
    )!;

    expect(choice.nowUnits(3.3), closeTo(1.65, 1e-9));
    expect(plan.parts.map((part) => part.pulses), [8, 8, 8, 9]);
    expect(plan.remainingUnitsAt(confirmedAt), closeTo(1.65, 1e-9));
    expect(plan.parts.first.at, confirmedAt.add(const Duration(minutes: 15)));
    expect(plan.endsAt, confirmedAt.add(const Duration(minutes: 60)));
  });

  test('a small rest skips the parts that would carry no pulse', () {
    final plan = SplitBolusPlan.spread(
      2,
      over: const Duration(minutes: 60),
      from: confirmedAt,
      glucoseMgdl: 120,
      mealKey: 1,
    );

    expect(plan.parts.map((part) => part.pulses), [1, 1]);
  });

  test('the plan survives the store and moves on part by part', () async {
    final backing = <String, String>{};
    final store = PodStore(FakeSecureStorage(backing), backing);
    const choice = SplitBolusChoice(
      enabled: true,
      nowPercent: 0,
      overMinutes: 30,
    );
    await store.saveSplitBolus(
      choice.plan(1, from: confirmedAt, glucoseMgdl: 120, mealKey: 1)!,
    );

    final stored = store.splitBolus!;

    expect(stored.parts.length, 2);
    expect(stored.afterFirst!.parts.single.pulses, 10);
    expect(stored.afterFirst!.afterFirst, isNull);
  });

  test('the planned rest counts as insulin on board in full', () async {
    final backing = <String, String>{};
    final store = PodStore(FakeSecureStorage(backing), backing);
    await store.saveSplitBolus(
      SplitBolusPlan.spread(
        40,
        over: const Duration(minutes: 60),
        from: confirmedAt,
        glucoseMgdl: 120,
        mealKey: 1,
      ),
    );

    final onBoard = const InsulinOnBoard(
      Duration(hours: 3),
    ).total(const [], pod: store, now: confirmedAt);

    expect(onBoard, closeTo(2, 1e-9));
  });

  test('a lapsed part stops counting and marks the plan as missed', () {
    final plan = SplitBolusPlan.spread(
      20,
      over: const Duration(minutes: 30),
      from: confirmedAt,
      glucoseMgdl: 120,
      mealKey: 1,
    );
    final firstLapsed = confirmedAt.add(const Duration(minutes: 31));

    expect(plan.remainingUnitsAt(firstLapsed), closeTo(0.5, 1e-9));
    expect(plan.missedAt(firstLapsed), isTrue);
    expect(
      plan.missedAt(confirmedAt.add(const Duration(minutes: 29))),
      isFalse,
    );
    expect(plan.remainingUnitsAt(confirmedAt.add(const Duration(hours: 1))), 0);
  });

  test('the send mark survives the store and settles off again', () async {
    final backing = <String, String>{};
    final store = PodStore(FakeSecureStorage(backing), backing);
    final plan = SplitBolusPlan.spread(
      20,
      over: const Duration(minutes: 30),
      from: confirmedAt,
      glucoseMgdl: 120,
      mealKey: 1,
    );
    await store.saveSplitBolus(plan.sendingAt(confirmedAt));

    final marked = store.splitBolus!;

    expect(marked.sendingSince, confirmedAt);
    expect(marked.settled.sendingSince, isNull);
    expect(marked.afterFirst!.sendingSince, isNull);
    expect(marked.settled.parts.length, 2);
  });

  /// Readings every five minutes up to [now], ending at [last] and moving by
  /// [perFiveMinutes] each step.
  LoopGlucose glucoseEnding(int last, int perFiveMinutes) {
    final now = DateTime(2026, 11, 9, 18, 30);
    final newest = now.millisecondsSinceEpoch ~/ 60000;
    final archive = SplayTreeMap<int, int>();
    for (var step = 0; step < 6; step++) {
      archive[newest - step * 5] = last - step * perFiveMinutes;
    }
    return LoopGlucose.from(archive, now: now);
  }

  test('the low guard stops the rest at or heading below the low line', () {
    const guard = SplitBolusLowGuard(70);

    expect(guard.stops(glucoseEnding(150, 0)), isFalse);
    expect(guard.stops(glucoseEnding(68, 0)), isTrue);
    expect(guard.stops(glucoseEnding(100, -8)), isTrue);
    expect(guard.stops(glucoseEnding(100, 2)), isFalse);
  });

  test('without usable sensor data the low guard lets the part go', () {
    final none = LoopGlucose.from(
      SplayTreeMap<int, int>(),
      now: DateTime(2026, 11, 9),
    );

    expect(const SplitBolusLowGuard(70).stops(none), isFalse);
  });

  test('a part keeps its meal link through the JSON round trip', () {
    final part = Meal(
      time: confirmedAt,
      carbs: 0,
      glucoseMgdl: 120,
      bolus: 0.5,
      entries: const [],
      deliveredByPump: true,
      splitOf: 1700000000000,
    );
    final plain = Meal(
      time: confirmedAt,
      carbs: 20,
      glucoseMgdl: 120,
      bolus: 1,
      entries: const [],
    );

    expect(Meal.fromJson(part.toJson()).splitOf, 1700000000000);
    expect(Meal.fromJson(part.toJson()).toJson(), part.toJson());
    expect(plain.toJson().containsKey('split_of'), isFalse);
  });
}
