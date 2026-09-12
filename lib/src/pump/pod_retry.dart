import 'package:insulink/src/pump/loop/loop_pod_commands.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_link_lease.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';

/// Runs a pod operation again when the attempt failed before anything reached
/// the pod.
///
/// The pod's link is a fragile thing to hold: it drops connections, refuses a
/// session opened too soon after the last one closed, and goes quiet when it is
/// asked for several things in a row. Most of those failures happen during the
/// connect and handshake, with no command sent, and reporting them to the user
/// as "it did not work" when trying once more would have worked is its own kind
/// of wrong answer.
///
/// **The boundary this class exists to hold is what may NOT be retried.** A
/// command that went out and was never answered may have been carried out. Doing
/// it again is a second dose, and no amount of link trouble makes that
/// acceptable. So [mayRetry] is a deny-list of outcomes that are not safe or not
/// useful to repeat, and everything else, which is every failure that happened
/// before a command was sent, is tried again.
///
/// The pod is left alone for longer between each attempt. Hammering it is what
/// causes some of these failures in the first place, and this sits on top of the
/// settle window `PodConnection` already waits out.
class PodRetry {
  const PodRetry({
    this.attempts = 3,
    this.firstDelay = const Duration(seconds: 2),
    this.onLog,
  });

  /// Total tries, not extra ones. Three is two more chances than before and
  /// still bounded: a bolus that cannot be sent in three attempts across roughly
  /// half a minute is not going to be sent by trying a fourth time, and the user
  /// is waiting for an answer.
  final int attempts;

  /// The wait before the second try, doubling for each one after it. Zero makes
  /// the retries immediate, which is what tests want and what nothing else
  /// should: leaving the pod alone between attempts is half the point.
  final Duration firstDelay;

  final void Function(String line)? onLog;

  /// Runs [body], repeating it while the failure is one that left the pod
  /// untouched. The last failure is rethrown when the attempts run out, so the
  /// caller reports exactly what it would have reported without any of this.
  Future<T> run<T>(String what, Future<T> Function() body) async {
    var delay = firstDelay;
    for (var attempt = 1; ; attempt++) {
      try {
        return await body();
      } catch (error) {
        if (attempt >= attempts || !mayRetry(error)) {
          rethrow;
        }
        onLog?.call('pod $what failed (try $attempt of $attempts): $error');
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        delay *= 2;
      }
    }
  }

  /// The same policy with somewhere to report its attempts.
  PodRetry copyWith({void Function(String line)? onLog}) => PodRetry(
    attempts: attempts,
    firstDelay: firstDelay,
    onLog: onLog ?? this.onLog,
  );

  /// Whether [error] left the pod in a state where doing the same thing again is
  /// both safe and worth trying.
  ///
  /// The three that are not:
  ///
  ///  * [PodCommandOutcomeUnknown] means a command was sent and never answered.
  ///    The pod may have run it. This is the one that would turn a lost
  ///    confirmation into a double dose, and it is why this is a deny-list and
  ///    not a list of retryable link errors: a new failure mode nobody thought
  ///    of gets retried, and only outcomes known to be unsafe are excluded.
  ///  * [PodBolusRefused] is a guard declining the dose against the pod's own
  ///    freshly read state. Nothing about repeating the request changes it.
  ///  * [LoopCommandRefused] is the pod itself declining. Same.
  ///  * [PodLinkBusy] is another part of the app holding the link. Safe to
  ///    repeat, but pointless: [PodLinkLease] already waits as long as the
  ///    caller wants to, so retrying is a SECOND wait loop stacked on the first.
  ///    It turns one lost race into three real connect attempts against a radio
  ///    somebody else is using, which is the contention rather than a cure for
  ///    it. The service comes back on its next tick and the UI tells the user.
  static bool mayRetry(Object error) {
    return error is! PodCommandOutcomeUnknown &&
        error is! PodBolusRefused &&
        error is! LoopCommandRefused &&
        error is! PodLinkBusy;
  }
}
