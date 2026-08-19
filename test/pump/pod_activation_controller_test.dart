import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_activation_controller.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_activation_state.dart';

import 'package:insulink/src/pump/pod_ble_permissions.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  late PodStore store;

  /// Permissions are asked for before the first scan; the tests grant them so the
  /// gate and stage logic is what is being exercised.
  const grantedPermissions = _GrantedPermissions();

  PodActivationController controllerWith({
    bool gateOpen = true,
    bool confirmCannula = true,
  }) =>
      PodActivationController(
        store: store,
        gate: PodDeliveryGate(gateOpen),
        confirmCannulaInsertion: () async => confirmCannula,
        permissions: grantedPermissions,
      );

  setUp(() {
    backing = <String, String>{};
    store = PodStore(FakeSecureStorage(backing), backing);
  });

  group('the stored step drives where the wizard resumes', () {
    test('a fresh app starts at the explanation', () {
      final controller = controllerWith();
      expect(controller.storedStep, PodActivationStep.notStarted);
      expect(controller.canResume, isFalse);
      controller.restoreStage();
      expect(controller.stage, PodActivationStage.explaining);
    });

    test('an activation interrupted before priming resumes at the start', () async {
      await store.saveActivationStep(PodActivationStep.identitySet.name);
      final controller = controllerWith();
      expect(controller.storedStep, PodActivationStep.identitySet);
      expect(controller.canResume, isTrue);
      controller.restoreStage();
      expect(controller.stage, PodActivationStage.explaining);
    });

    test('a primed pod resumes at the attach step', () async {
      await store.saveActivationStep(PodActivationStep.primed.name);
      final controller = controllerWith()..restoreStage();
      expect(controller.stage, PodActivationStage.attachPod);
      expect(controller.canResume, isTrue);
    });

    test('a running pod is not an activation to resume', () async {
      await store.saveActivationStep(PodActivationStep.running.name);
      final controller = controllerWith()..restoreStage();
      expect(controller.stage, PodActivationStage.running);
      expect(controller.canResume, isFalse);
    });

    test('an unrecognised stored step reads as not started, never as done', () async {
      await store.saveActivationStep('somethingElse');
      final controller = controllerWith();
      expect(controller.storedStep, PodActivationStep.notStarted);
      controller.restoreStage();
      expect(controller.stage, PodActivationStage.explaining);
    });
  });

  group('what the pod reported survives the app being restarted', () {
    /// The two commands that produce these numbers cannot be repeated — the pod
    /// stops answering on the discovery id once it has one of its own — so a
    /// resumed activation works from the record or not at all.
    test('a stored record is what a resumed wizard primes from', () async {
      await store.saveActivationFacts(jsonEncode(const PodActivationFacts(
        uniqueId: 4241,
        lotNumber: 135,
        podSequenceNumber: 7,
        primePulses: 52,
        cannulaInsertionPulses: 10,
        primePumpRateEighthSeconds: 8,
        expirationHours: 80,
      ).toJson()));

      final controller = controllerWith();

      expect(controller.facts?.primePulses, 52);
      expect(controller.facts?.cannulaInsertionPulses, 10);
      expect(controller.facts?.expirationHours, 80);
    });

    test('nothing recorded reads as nothing, not as a default dose', () {
      expect(controllerWith().facts, isNull);
    });
  });


  group('the delivery gate is checked before anything is sent', () {
    test('priming is refused while the gate is shut', () async {
      final controller = controllerWith(gateOpen: false);
      await controller.primePod();
      expect(controller.stage, PodActivationStage.failed);
      expect(controller.failure, contains('locked'));
    });

    test('the gate is checked before a scan, so no pod is touched', () async {
      // A shut gate must fail without reaching the radio; if it did reach it, the
      // test host has no Bluetooth and the failure would name that instead.
      final controller = controllerWith(gateOpen: false);
      await controller.primePod();
      expect(controller.failure, isNot(contains('Bluetooth')));
      expect(controller.isBusy, isFalse);
    });
  });

  group('discarding an attempt', () {
    test('forgets the pod and returns to the explanation', () async {
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: FakeSecureStorage.dummyKey,
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime.now(),
      );
      await store.saveActivationStep(PodActivationStep.primed.name);
      final controller = controllerWith()..restoreStage();
      expect(controller.stage, PodActivationStage.attachPod);

      await controller.discardAttempt();

      expect(store.hasPod, isFalse);
      expect(store.activationStep, isNull);
      expect(controller.stage, PodActivationStage.explaining);
      expect(controller.facts, isNull);
    });
  });

  group('PodActivationStep ordering', () {
    test('the steps are ordered as the activation runs them', () {
      expect(
        PodActivationStep.notStarted.isBefore(PodActivationStep.gotVersion),
        isTrue,
      );
      expect(PodActivationStep.priming.isBefore(PodActivationStep.primed), isTrue);
      expect(PodActivationStep.primed.isBefore(PodActivationStep.basalSet), isTrue);
      expect(
        PodActivationStep.insertingCannula.isBefore(PodActivationStep.running),
        isTrue,
      );
      expect(PodActivationStep.running.isBefore(PodActivationStep.primed), isFalse);
    });
  });

  group('a resume knows whether the pod is already on the body', () {
    test('a primed pod is not yet attached', () async {
      await store.saveActivationStep(PodActivationStep.primed.name);
      expect(controllerWith().isAlreadyAttached, isFalse);
    });

    /// Basal is only ever programmed after the user confirmed the pod is on, so
    /// anything past that proves it — and telling them to attach it again would be
    /// wrong.
    test('a pod past basal programming is attached', () async {
      await store.saveActivationStep(PodActivationStep.basalSet.name);
      expect(controllerWith().isAlreadyAttached, isTrue);
    });

    test('a pod mid cannula insertion is attached', () async {
      await store.saveActivationStep(PodActivationStep.insertingCannula.name);
      expect(controllerWith().isAlreadyAttached, isTrue);
    });

    test('a finished activation is not a resume', () async {
      await store.saveActivationStep(PodActivationStep.running.name);
      expect(controllerWith().isAlreadyAttached, isFalse);
    });

    test('a fresh activation is not a resume', () {
      expect(controllerWith().isAlreadyAttached, isFalse);
    });
  });

  group('the permission prompt comes before anything touches the radio', () {
    test('a refusal stops the activation with a clear reason', () async {
      final controller = PodActivationController(
        store: store,
        gate: PodDeliveryGate(true),
        confirmCannulaInsertion: () async => true,
        permissions: const _DeniedPermissions(),
      );
      await controller.primePod();
      expect(controller.stage, PodActivationStage.failed);
      expect(controller.failure, contains('Bluetooth'));
    });
  });

  group('discarding is refused once the pod may be delivering', () {
    /// The one outcome the whole design exists to prevent: forgetting the key to a
    /// pod that is in the body and running, which then cannot be stopped by
    /// anything.
    test('a pod whose cannula went in is not discarded', () async {
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 3)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
      );
      await store.saveActivationStep(PodActivationStep.insertingCannula.name);
      final controller = controllerWith();

      await controller.discardAttempt();

      expect(store.hasPod, isTrue);
      expect(controller.failureKey, 'pump.activate.discard_refused');
    });

    test('a running pod is not discarded either', () async {
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 3)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
      );
      await store.saveActivationStep(PodActivationStep.running.name);
      final controller = controllerWith();

      await controller.discardAttempt();

      expect(store.hasPod, isTrue);
    });

    /// A pod that was only primed has insulin in it but nothing in the body, so
    /// throwing it away is exactly right.
    test('a primed pod is discarded, and everything about it is cleared', () async {
      await store.savePairing(
        uniqueId: 4241,
        longTermKey: Uint8List.fromList(List<int>.filled(16, 3)),
        lotNumber: 1,
        podSequenceNumber: 2,
        activatedAt: DateTime(2026, 3, 1),
      );
      await store.saveActivationStep(PodActivationStep.primed.name);
      final controller = controllerWith();

      await controller.discardAttempt();

      expect(store.hasPod, isFalse);
      expect(controller.stage, PodActivationStage.explaining);
      expect(controller.facts, isNull);
    });
  });
}

/// Stands in for the platform permission prompt, which cannot run in a test.
class _GrantedPermissions implements PodBlePermissions {
  const _GrantedPermissions();

  @override
  Future<bool> ensure() async => true;
}

/// A user who declines the Bluetooth prompt.
class _DeniedPermissions implements PodBlePermissions {
  const _DeniedPermissions();

  @override
  Future<bool> ensure() async => false;
}
