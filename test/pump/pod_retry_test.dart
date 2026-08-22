import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_pod_commands.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_link_lease.dart';
import 'package:insulink/src/pump/pod_retry.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';

void main() {
  const immediate = PodRetry(attempts: 3, firstDelay: Duration.zero);

  group('what may be tried again', () {
    /// Everything that fails during the connect or the handshake left the pod
    /// with nothing asked of it, so repeating costs nothing but time.
    test('a link that never came up', () {
      expect(PodRetry.mayRetry(PodLinkException('no pod in range')), isTrue);
    });

    test('a session the pod would not establish', () {
      expect(PodRetry.mayRetry(PodSessionException('rejected twice')), isTrue);
    });

    /// The deny-list is deliberately short and the default is to retry, so a
    /// failure mode nobody has thought of yet gets another chance rather than
    /// being reported as final.
    test('an error nobody classified', () {
      expect(PodRetry.mayRetry(StateError('something from a plugin')), isTrue);
    });
  });

  group('what may NOT be tried again', () {
    /// The one that matters. A command that went out and was never answered may
    /// have been carried out, and doing it again is a second dose. No amount of
    /// link trouble makes that acceptable.
    test('a command whose outcome is unknown', () {
      expect(
        PodRetry.mayRetry(PodCommandOutcomeUnknown('Pod sent no reply')),
        isFalse,
      );
    });

    test('a dose a guard refused', () {
      expect(PodRetry.mayRetry(PodBolusRefused('already bolusing')), isFalse);
    });

    test('a command the pod itself refused', () {
      expect(PodRetry.mayRetry(LoopCommandRefused('podState')), isFalse);
    });
  });

  group('how it runs', () {
    test('a first attempt that works is the only attempt', () async {
      var tries = 0;

      final result = await immediate.run('thing', () async {
        tries++;
        return 'done';
      });

      expect(result, 'done');
      expect(tries, 1);
    });

    test('it keeps trying up to the limit and then gives up', () async {
      var tries = 0;

      await expectLater(
        immediate.run<void>('thing', () async {
          tries++;
          throw PodLinkException('no pod in range');
        }),
        throwsA(isA<PodLinkException>()),
      );

      expect(tries, 3);
    });

    test('it stops as soon as one works', () async {
      var tries = 0;

      final result = await immediate.run('thing', () async {
        tries++;
        if (tries < 2) {
          throw PodLinkException('no pod in range');
        }
        return tries;
      });

      expect(result, 2);
    });

    /// The failure the caller sees is the real one, so a retry that could not
    /// help does not change what the user is told.
    test('an unknown outcome is thrown straight out on the first try', () async {
      var tries = 0;

      await expectLater(
        immediate.run<void>('bolus', () async {
          tries++;
          throw PodCommandOutcomeUnknown('Pod sent no reply');
        }),
        throwsA(isA<PodCommandOutcomeUnknown>()),
      );

      expect(tries, 1, reason: 'a possibly-delivered dose is never repeated');
    });

    test('the last failure is what reaches the caller', () async {
      await expectLater(
        immediate.run<void>('thing', () async {
          throw PodSessionException('rejected twice');
        }),
        throwsA(
          isA<PodSessionException>().having(
            (error) => error.message,
            'message',
            'rejected twice',
          ),
        ),
      );
    });
  });

  /// A busy link is not a pod failure and nothing was sent, so repeating it is
  /// safe. It is excluded anyway: [PodLinkLease] already waits as long as the
  /// caller asked it to, so a retry is a second wait loop stacked on the first,
  /// and it turns one lost race into three real connect attempts against a radio
  /// another part of the app is using.
  test('a busy link is not retried', () async {
    var attempts = 0;

    await expectLater(
      const PodRetry(attempts: 3, firstDelay: Duration.zero).run('poll', () {
        attempts++;
        throw PodLinkBusy('the app');
      }),
      throwsA(isA<PodLinkBusy>()),
    );

    expect(attempts, 1);
  });
}
