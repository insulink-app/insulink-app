import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/injection/split_bolus_choice.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/split_bolus.dart';

import 'fake_secure_storage.dart';

void main() {
  final confirmedAt = DateTime(2026, 11, 9, 18);

  test('off, the whole dose goes out at once and nothing is planned', () {
    const choice = SplitBolusChoice();

    expect(choice.nowUnits(3.3), 3.3);
    expect(choice.plan(3.3, from: confirmedAt, glucoseMgdl: 120), isNull);
  });

  test('a split gives its share now and spreads every pulse of the rest', () {
    const choice = SplitBolusChoice(
      enabled: true,
      nowPercent: 50,
      overMinutes: 60,
    );

    final plan = choice.plan(3.3, from: confirmedAt, glucoseMgdl: 120)!;

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
      choice.plan(1, from: confirmedAt, glucoseMgdl: 120)!,
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
    );
    await store.saveSplitBolus(plan.sendingAt(confirmedAt));

    final marked = store.splitBolus!;

    expect(marked.sendingSince, confirmedAt);
    expect(marked.settled.sendingSince, isNull);
    expect(marked.afterFirst!.sendingSince, isNull);
    expect(marked.settled.parts.length, 2);
  });
}
