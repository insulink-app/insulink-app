import 'package:insulink/src/pump/loop/loop_micro_bolus_settings.dart';
import 'package:insulink/src/pump/pod_controller.dart';

/// Lets a manual bolus wait for a micro bolus the automation is still giving.
///
/// The pod refuses a bolus while another one runs. A micro bolus takes about
/// two seconds per 0.05 U, so without this a meal bolus confirmed in that window
/// would be refused and the user would have to try again. Instead it waits, up to
/// the user's limit ([LoopMicroBolusSettings.queueSeconds]), and is sent once
/// the pod is free.
///
/// Only an AUTOMATED bolus is waited for. A manual one still running means the
/// user tapped twice, and queueing that would be a second dose.
///
/// Waits BEFORE the dose is recorded as pending, so an app killed while waiting
/// leaves no trace of a dose that was never sent.
class MicroBolusQueue {
  const MicroBolusQueue({this.sleep = Future<void>.delayed});

  /// How the wait is spent. Injectable so tests do not wait in real time.
  final Future<void> Function(Duration) sleep;

  /// Extra time after the micro bolus should have finished, for the last pulse
  /// and for a startedAt stamped a moment before the pod accepted it.
  static const Duration settle = Duration(seconds: 3);

  /// Waits out a running micro bolus and returns null once the pod is free, or
  /// returns the time it still has to run when that is longer than the user's
  /// limit, without waiting.
  ///
  /// The store is re-read first: the micro bolus was written by the service
  /// isolate, and this one's copy of the store cannot have seen it.
  Future<Duration?> waitFor(PodController controller) async {
    await controller.store.reload();
    final running = controller.runningBolus;
    if (running == null || !running.automated) {
      return null;
    }
    controller.notifyRunningBolusChanged();
    final remaining = running.remaining(DateTime.now());
    final limit = Duration(
      seconds: await LoopMicroBolusSettings.queueSeconds.load(),
    );
    if (remaining > limit) {
      return remaining;
    }
    await sleep(remaining + settle);
    return null;
  }
}
