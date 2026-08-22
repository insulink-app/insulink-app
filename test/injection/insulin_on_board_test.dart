import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/pod_store.dart';

import '../pump/fake_secure_storage.dart';

/// The incident this file exists for: while the automation ran an elevated
/// temporary basal, the insulin it had added was real, was in the body, and the
/// bolus calculator could not see it, so it suggested a full correction on top.
/// At the configured ceilings that is up to 4 U, around 140 mg/dL of correction
/// nobody needed.
void main() {
  const duration = Duration(hours: 3);
  final now = DateTime(2026, 5, 4, 21, 30);

  late Map<String, String> backing;
  late PodStore store;

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  Meal bolusAt(DateTime time, double units) => Meal(
        time: time,
        carbs: 0,
        glucoseMgdl: 0,
        bolus: units,
        entries: const [],
      );

  /// An hour of the automation running [rate] against a [schedule].
  Future<void> automationRan({
    required double rate,
    required double schedule,
    required int minutesAgo,
    required int lastedMinutes,
  }) async {
    final start = now.subtract(Duration(minutes: minutesAgo));
    await store.recordLoopCycle(PodLoopCycle(
      at: start,
      unitsPerHour: rate,
      scheduledUnitsPerHour: schedule,
      reason: LoopReason.correcting,
      delivered: true,
    ));
    await store.recordLoopCycle(PodLoopCycle(
      at: start.add(Duration(minutes: lastedMinutes)),
      unitsPerHour: schedule,
      scheduledUnitsPerHour: schedule,
      reason: LoopReason.holdingSchedule,
      delivered: true,
    ));
  }

  group('what the calculator was blind to', () {
    test('the automation is on board even with no logged dose', () async {
      await automationRan(
        rate: 3.0,
        schedule: 1.0,
        minutesAgo: 40,
        lastedMinutes: 30,
      );

      final parts = InsulinOnBoard(duration).parts(const [], pod: store, now: now);

      expect(parts.boluses, 0);
      expect(parts.automation, greaterThan(0.5));
      expect(parts.total, parts.automation);
    });

    /// The heart of it, on the shape real operation has: a cycle every five
    /// minutes, each replacing the last, for an hour at 3 U/h against a 1 U/h
    /// schedule. Two units of excess went in, and the calculator used to
    /// subtract none of it.
    test('an hour of elevated basal is on board, and the meal log misses it',
        () async {
      final meals = [bolusAt(now.subtract(const Duration(minutes: 30)), 2.0)];
      for (var minutesAgo = 60; minutesAgo > 0; minutesAgo -= 5) {
        await store.recordLoopCycle(PodLoopCycle(
          at: now.subtract(Duration(minutes: minutesAgo)),
          unitsPerHour: 3.0,
          scheduledUnitsPerHour: 1.0,
          reason: LoopReason.correcting,
          delivered: true,
        ));
      }

      final parts = InsulinOnBoard(duration).parts(meals, pod: store, now: now);

      expect(parts.boluses, closeTo(1.667, 0.01));
      expect(parts.automation, greaterThan(1.5),
          reason: 'two units went in over the hour, most of it still active');
      expect(parts.total, greaterThan(parts.boluses + 1.5));
    });

    /// A cycle nothing replaced stops counting at the fuse: past it the pod has
    /// returned to its schedule on its own, so an hour-old lone cycle carries
    /// half an hour of excess, not an hour of it.
    test('a lone cycle is billed only to the end of its fuse', () async {
      await automationRan(
        rate: 3.0,
        schedule: 1.0,
        minutesAgo: 90,
        lastedMinutes: 60,
      );

      final parts = InsulinOnBoard(duration).parts(const [], pod: store, now: now);

      expect(parts.automation, closeTo(0.583, 0.01));
    });

    /// A dose the pod never confirmed may be in the body, and no correction
    /// should be stacked on top of one.
    test('an unconfirmed dose counts too', () async {
      await store.recordUnconfirmedBolus(PodDelivery(
        at: now.subtract(const Duration(minutes: 30)),
        units: 6,
        kind: PodDeliveryKind.bolus,
      ));

      final parts = InsulinOnBoard(duration).parts(const [], pod: store, now: now);

      expect(parts.unconfirmed, closeTo(5.0, 0.01));
      expect(parts.beyondBoluses, closeTo(5.0, 0.01));
    });
  });

  /// The three pots must not overlap, or the calculator subtracts a dose twice
  /// and refuses insulin that is genuinely needed.
  group('nothing is counted twice', () {
    test('a confirmed pump bolus lives in the meal log alone', () async {
      final meals = [bolusAt(now.subtract(const Duration(minutes: 30)), 4.0)];
      // What the pod's own delivery log holds for that same dose. It feeds the
      // hourly ceiling, never insulin on board.
      await store.recordDelivery(PodDelivery(
        at: now.subtract(const Duration(minutes: 30)),
        units: 4.0,
        kind: PodDeliveryKind.bolus,
      ));

      final parts = InsulinOnBoard(duration).parts(meals, pod: store, now: now);

      expect(parts.beyondBoluses, 0);
      expect(parts.total, closeTo(parts.boluses, 1e-9));
    });

    /// Priming and cannula volumes never reach the user.
    test('activation volumes are not insulin on board', () async {
      for (final kind in [PodDeliveryKind.prime, PodDeliveryKind.cannula]) {
        await store.recordDelivery(PodDelivery(
          at: now.subtract(const Duration(minutes: 20)),
          units: 2.6,
          kind: kind,
        ));
      }

      expect(
        InsulinOnBoard(duration).parts(const [], pod: store, now: now).total,
        0,
      );
    });
  });

  group('what must NOT be counted', () {
    /// Scheduled basal is maintenance, offsetting the glucose the liver
    /// releases. Counting it would have the calculator refuse a correction
    /// because twelve units went in today.
    test('the schedule itself is not insulin on board', () async {
      await automationRan(
        rate: 1.0,
        schedule: 1.0,
        minutesAgo: 60,
        lastedMinutes: 30,
      );

      expect(
        InsulinOnBoard(duration).parts(const [], pod: store, now: now).automation,
        0,
      );
    });

    /// Withholding background insulin is not the same as removing insulin from
    /// the body. Counting it as negative would INFLATE the next suggestion on
    /// the strength of a dose nobody gave.
    test('running below schedule never counts as negative', () async {
      await automationRan(
        rate: 0,
        schedule: 2.0,
        minutesAgo: 60,
        lastedMinutes: 30,
      );

      expect(
        InsulinOnBoard(duration).parts(const [], pod: store, now: now).automation,
        0,
      );
    });

    test('no pump at all leaves only the boluses', () {
      final meals = [bolusAt(now.subtract(const Duration(minutes: 30)), 2.0)];

      final parts = InsulinOnBoard(duration).parts(meals, now: now);

      expect(parts.beyondBoluses, 0);
      expect(parts.total, parts.boluses);
    });
  });

  /// The suggestion has to actually come down by what is on board, or none of
  /// the above matters.
  group('the suggestion shrinks by what is on board', () {
    final profile = ProfileBolusState(
      correctionFactor: 35,
      carbFactor: 15,
      maxBolus: 10,
      insulinDurationH: 3,
    );

    test('automated insulin reduces the correction', () {
      final blind = profile.suggestedBolus(
        carbs: 0,
        glucoseMgdl: 200,
        targetMgdl: 110,
        iobUnits: 0,
      );
      final seeing = profile.suggestedBolus(
        carbs: 0,
        glucoseMgdl: 200,
        targetMgdl: 110,
        iobUnits: 2.0,
      );

      expect(blind - seeing, closeTo(2.0, 1e-9));
    });

    /// Two units of unseen insulin at a correction factor of 35 is 70 mg/dL of
    /// correction that should never have been given.
    test('what being blind to two units was worth', () {
      final overdose = profile.suggestedBolus(
            carbs: 0,
            glucoseMgdl: 200,
            targetMgdl: 110,
            iobUnits: 0,
          ) -
          profile.suggestedBolus(
            carbs: 0,
            glucoseMgdl: 200,
            targetMgdl: 110,
            iobUnits: 2.0,
          );

      expect(overdose * profile.correctionFactor, closeTo(70, 1e-6));
    });
  });
}
