import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/injection/insulin_on_board_curve.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/pod_store.dart';

import '../pump/fake_secure_storage.dart';

void main() {
  const duration = Duration(hours: 3);
  final now = DateTime(2026, 10, 14, 18, 30);
  late PodStore store;

  setUp(() {
    final backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  Meal mealAt(DateTime time, double bolus) => Meal(
    time: time,
    carbs: 40,
    glucoseMgdl: 120,
    bolus: bolus,
    entries: const [],
  );

  InsulinOnBoardSample sampleAt(
    List<InsulinOnBoardSample> samples,
    DateTime at,
  ) => samples.firstWhere((sample) => sample.at == at);

  /// The graph and the number above it are the same quantity.
  test('at now the layers add up to the insulin on board', () async {
    final meals = [mealAt(now.subtract(const Duration(minutes: 40)), 4)];
    await store.recordLoopCycle(
      PodLoopCycle(
        at: now.subtract(const Duration(minutes: 30)),
        unitsPerHour: 3,
        scheduledUnitsPerHour: 1,
        reason: LoopReason.correcting,
        delivered: true,
      ),
    );
    await store.bookLoopMicroBolus(
      0.5,
      now.subtract(const Duration(minutes: 10)),
    );

    final samples = const InsulinOnBoardCurve(
      duration,
    ).samples(meals, pod: store, now: now);
    final atNow = sampleAt(samples, now);

    expect(atNow.boluses, greaterThan(0));
    expect(atNow.microBoluses, greaterThan(0));
    expect(atNow.rate, greaterThan(0));
    expect(
      atNow.total,
      closeTo(
        const InsulinOnBoard(duration).total(meals, pod: store, now: now),
        1e-9,
      ),
    );
  });

  test('a micro bolus counts nothing before it was given', () async {
    final given = now.subtract(const Duration(minutes: 20));
    await store.bookLoopMicroBolus(0.5, given);

    final samples = const InsulinOnBoardCurve(
      duration,
    ).samples(const [], pod: store, now: now);

    expect(samples.first.at, given);
    expect(sampleAt(samples, given).microBoluses, closeTo(0.5, 1e-9));
  });

  /// Ahead of now only the insulin already in decays. The rate still running
  /// must not grow the curve with insulin not yet delivered.
  test('the rate running now is not projected forward', () async {
    await store.recordLoopCycle(
      PodLoopCycle(
        at: now.subtract(const Duration(minutes: 10)),
        unitsPerHour: 4,
        scheduledUnitsPerHour: 1,
        reason: LoopReason.correcting,
        delivered: true,
      ),
    );

    final samples = const InsulinOnBoardCurve(
      duration,
    ).samples(const [], pod: store, now: now);
    final later = sampleAt(samples, now.add(const Duration(minutes: 20)));

    expect(later.rate, lessThan(sampleAt(samples, now).rate));
  });

  test('nothing on board gives no curve', () {
    expect(
      const InsulinOnBoardCurve(
        duration,
      ).samples(const [], pod: store, now: now),
      isEmpty,
    );
  });
}
