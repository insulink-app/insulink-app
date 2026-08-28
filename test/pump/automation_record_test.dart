import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

import 'fake_secure_storage.dart';

/// The basal analysis has to be able to ask "was the automation running during
/// this hour?" about hours from weeks ago. It used to ask the pod's own ledger,
/// which [PodStore.forgetPod] clears, and a pod lives eighty hours: the record
/// reset every three days and was empty the morning after a pod change, so every
/// hour became unanswerable and the analysis found nothing at all.
void main() {
  late Map<String, String> backing;
  late PodStore store;
  final hour = DateTime(2026, 5, 4, 3);

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  test('nothing is known before the first booking', () {
    expect(store.automationCoveredSince, isNull);
    expect(store.automationExcessInHour(hour), 0);
  });

  /// From the first booking on, an hour with no entry is an hour with no
  /// excess. That is what makes a zero mean something.
  /// The whole point of starting on engage rather than on the first booking: a
  /// pod user who never switches the automation on has nothing to clear, and
  /// demanding a clearance from them left the analysis with no hours at all.
  test('booking alone never starts the span', () async {
    await store.recordAutomationExcess(hour, 1.2);

    expect(store.automationCoveredSince, isNull);
    expect(store.automationExcessInHour(hour), 0);
  });

  test('switching the automation on starts the span', () async {
    await store.saveLoopMode(PodLoopMode.engaged);

    expect(store.automationCoveredSince, isNotNull);
  });

  test('switching it on again does not move the span', () async {
    await store.saveLoopMode(PodLoopMode.engaged);
    final started = store.automationCoveredSince;
    await store.saveLoopMode(PodLoopMode.off);
    await store.saveLoopMode(PodLoopMode.engaged);

    expect(store.automationCoveredSince, started);
  });

  test('excess is remembered for the hour it fell in', () async {
    await store.startAutomationRecord();
    await store.recordAutomationExcess(hour.add(const Duration(minutes: 40)), 1.2);

    expect(store.automationExcessInHour(hour), closeTo(1.2, 1e-9));
  });

  test('several bookings in one hour add up', () async {
    await store.startAutomationRecord();
    await store.recordAutomationExcess(hour, 0.4);
    await store.recordAutomationExcess(hour.add(const Duration(minutes: 30)), 0.5);

    expect(store.automationExcessInHour(hour), closeTo(0.9, 1e-9));
  });

  test('a quiet hour inside the span reports nothing', () async {
    await store.startAutomationRecord();

    expect(store.automationExcessInHour(hour.add(const Duration(hours: 5))), 0);
  });

  /// The point of the whole change: it is the user's insulin history, not the
  /// pod's, so throwing the pod away must not throw it away.
  test('it survives forgetting the pod', () async {
    await store.startAutomationRecord();
    await store.recordAutomationExcess(hour, 1.5);
    final started = store.automationCoveredSince;

    await store.forgetPod();

    expect(store.automationExcessInHour(hour), closeTo(1.5, 1e-9));
    expect(store.automationCoveredSince, started);
  });

  /// Only hours that carried excess are stored, so the cap is generous even for
  /// a loop that runs hot every night.
  test('the record stays bounded, keeping the newest hours', () async {
    await store.startAutomationRecord();
    for (var index = 0; index < PodAutomationRecord.maxHours + 20; index++) {
      await store.recordAutomationExcess(hour.add(Duration(hours: index)), 0.3);
    }

    expect(store.automationExcessInHour(hour), 0, reason: 'oldest dropped');
    expect(
      store.automationExcessInHour(
        hour.add(Duration(hours: PodAutomationRecord.maxHours + 19)),
      ),
      closeTo(0.3, 1e-9),
    );
  });

  test('a corrupted record reads as nothing rather than throwing', () async {
    backing['automation.excess_hours'] = 'not json';
    backing['automation.covered_since'] = '${hour.millisecondsSinceEpoch}';
    await store.reload();

    expect(store.automationExcessInHour(hour), 0);
  });

  /// Unused here, but it keeps the import honest about what a status is for.
  test('the store still answers about a pod', () {
    expect(PodLifecycleStatus.byValue(0x08).isRunning, isTrue);
  });
}
