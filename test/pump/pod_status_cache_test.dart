import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

import 'fake_secure_storage.dart';
import 'loop_input.dart';

/// The last status anyone read, kept so the pump page opens on something and so
/// the automation can decide while switched off without waking the pod.
void main() {
  late Map<String, String> backing;
  late PodStore store;
  final now = DateTime(2026, 5, 4, 9, 30);

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  // Running above minimum volume, delivering basal.
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));

  test('nothing is cached until a status is read', () {
    expect(store.lastStatus, isNull);
    expect(store.lastStatusAt, isNull);
  });

  /// The whole frame is stored rather than the decoded fields, so reading it
  /// back runs the same decoder and cannot drift from it.
  test('a stored status decodes back to the same values', () async {
    await store.saveLastStatus(running, now);
    await store.reload();

    final restored = store.lastStatus!;

    expect(restored.lifecycle, running.lifecycle);
    expect(restored.delivery, running.delivery);
    expect(restored.reservoirPulsesRemaining, running.reservoirPulsesRemaining);
    expect(restored.minutesSinceActivation, running.minutesSinceActivation);
    expect(store.lastStatusAt, now);
  });

  /// Written by whichever isolate last read the pod, so the page benefits from
  /// the background poll and the poll benefits from the page.
  test('a later read replaces an earlier one', () async {
    await store.saveLastStatus(running, now);
    final alarming = PodStatusResponse(hex('1D1D00A02800000463FF'));
    final later = now.add(const Duration(minutes: 5));

    await store.saveLastStatus(alarming, later);

    expect(store.lastStatus!.lifecycle, PodLifecycleStatus.alarm);
    expect(store.lastStatusAt, later);
  });

  /// The case a reinstall + restore produces: full credentials, no local trail of
  /// the activation, and a pod that has been running for a day. Without this the
  /// pump page offered to resume the wizard, and the poll, the watch and the loop
  /// all stood down.
  test('a pod reporting itself running counts as activated', () async {
    expect(store.isActivated, isFalse);

    await store.saveLastStatus(running, now);

    expect(store.isActivated, isTrue);
  });

  test('a pod that is not running is left where the wizard had it', () async {
    await store.saveActivationStep('priming');
    final alarming = PodStatusResponse(hex('1D1D00A02800000463FF'));

    await store.saveLastStatus(alarming, now);

    expect(store.activationStep, 'priming');
  });

  /// One-directional: a pod that stops running is not un-activated. That is a pod
  /// change, and it goes through [PodStore.forgetPod].
  test('an alarm does not take activation back', () async {
    await store.saveLastStatus(running, now);
    final alarming = PodStatusResponse(hex('1D1D00A02800000463FF'));

    await store.saveLastStatus(alarming, now.add(const Duration(minutes: 5)));

    expect(store.isActivated, isTrue);
  });

  test('a corrupted entry reads as nothing rather than throwing', () async {
    backing['pod.last_status'] = 'not json';
    await store.reload();

    expect(store.lastStatus, isNull);
    expect(store.lastStatusAt, isNull);
  });

  /// It describes the pod it was read from, so it dies with that pod.
  test('forgetting the pod forgets its status', () async {
    await store.saveLastStatus(running, now);
    await store.forgetPod();

    expect(store.lastStatus, isNull);
  });
}
