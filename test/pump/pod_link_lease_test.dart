import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/pod_link_lease.dart';
import 'package:insulink/src/pump/pod_retry.dart';

import 'fake_secure_storage.dart';

void main() {
  late Map<String, String> backing;
  final now = DateTime(2026, 5, 4, 9, 30);

  PodLinkLease leaseFor(String owner, {Duration patience = Duration.zero}) =>
      PodLinkLease(
        owner,
        patience: patience,
        storage: FakeSecureStorage(backing),
      );

  setUp(() => backing = <String, String>{});

  group('two isolates cannot hold the link at once', () {
    /// The failure this exists for: the UI isolate and the service isolate each
    /// connected, Android answered the second writer with
    /// ERROR_GATT_WRITE_REQUEST_BUSY, and the pod dropped both sessions. It looks
    /// exactly like a pod that blocks under too many commands.
    test('the second owner is turned away', () async {
      await leaseFor('the app').take(now: now);

      await expectLater(
        leaseFor('the background service').take(now: now),
        throwsA(isA<PodLinkBusy>()),
      );
    });

    test('the holder can take it again, so its own retries are not blocked',
        () async {
      final service = leaseFor('the background service');
      await service.take(now: now);

      await expectLater(service.take(now: now), completes);
    });

    /// The watch and the automation run chained on the same tick and share one
    /// owner, so neither can lock the other out of its own isolate.
    test('one owner covers everything inside an isolate', () async {
      await leaseFor('the background service').take(now: now);

      await expectLater(
        leaseFor('the background service').take(now: now),
        completes,
      );
    });

    test('the link is free again once it is released', () async {
      final app = leaseFor('the app');
      await app.take(now: now);
      await app.release();

      await expectLater(
        leaseFor('the background service').take(now: now),
        completes,
      );
    });
  });

  group('a lease cannot lock the pod away', () {
    /// A holder that is killed never releases anything, so the lease has to let
    /// go by itself. Otherwise one crash would put the pod out of reach.
    test('an expired lease is taken over', () async {
      await leaseFor('the app').take(now: now);
      final later = now.add(PodLinkLease.hold).add(const Duration(seconds: 1));

      await expectLater(
        leaseFor('the background service').take(now: later),
        completes,
      );
    });

    /// Releasing checks that the lease is still ours. Clearing one that expired
    /// and was taken over would pull it out from under its new holder.
    test('releasing a lease somebody else took does nothing', () async {
      final app = leaseFor('the app');
      await app.take(now: now);
      final later = now.add(PodLinkLease.hold).add(const Duration(seconds: 1));
      await leaseFor('the background service').take(now: later);

      await app.release();

      await expectLater(
        leaseFor('a third thing').take(now: later),
        throwsA(isA<PodLinkBusy>()),
      );
    });
  });

  group('waiting for it', () {
    /// The two sides want opposite things. A tap has to happen and a poll is
    /// seconds long, so the UI waits it out; the service comes back next tick.
    test('a patient owner waits and then gets it', () async {
      final service = leaseFor('the background service');
      await service.take(now: now);
      final app = leaseFor('the app', patience: const Duration(seconds: 2));

      final taking = app.take();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await service.release();

      await expectLater(taking, completes);
    });

    test('an impatient owner gives up at once', () async {
      await leaseFor('the app').take(now: now);
      final start = DateTime.now();

      await expectLater(
        leaseFor('the background service').take(now: now),
        throwsA(isA<PodLinkBusy>()),
      );

      expect(DateTime.now().difference(start),
          lessThan(const Duration(milliseconds: 200)));
    });

    test('a patient owner still gives up eventually', () async {
      await leaseFor('the background service').take(now: now);

      await expectLater(
        leaseFor('the app', patience: const Duration(milliseconds: 800))
            .take(now: now),
        throwsA(isA<PodLinkBusy>()),
      );
    });
  });

  /// Nothing was sent to the pod, so the operation is repeated rather than
  /// reported. That is what turns a collision into a short wait.
  test('a busy link is something the retry policy repeats', () {
    expect(PodRetry.mayRetry(PodLinkBusy('the app')), isTrue);
  });
}
