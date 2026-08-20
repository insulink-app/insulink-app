import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// Turning the automation on and off, with the pod put back where it belongs.
///
/// Split from [PodController] rather than added to it: the controller is already
/// the page's whole view of the pod, and mode changes are their own small job
/// with their own ordering rules.
///
/// The order is the point. Switching OFF writes the mode first and only then
/// tries to reach the pod, so a cancel that fails still leaves an app that has
/// stopped automating. The pod is not left running the last rate either way,
/// because that rate expires on its own within [LoopLimits.fuse]; reaching it now
/// only makes the schedule resume sooner.
class LoopSwitch {
  const LoopSwitch(this.controller);

  final PodController controller;

  PodStore get _store => controller.store;

  /// Why the automation cannot be engaged right now, or null when it can.
  ///
  /// Checked before the switch rather than reported after it, because a loop that
  /// engages and immediately stops itself teaches the user that the switch does
  /// not work.
  Future<String?> blockedReason() async {
    if (!_store.hasPod || !_store.isActivated) {
      return 'pump.loop.blocked.no_pod';
    }
    if (_store.basalRates == null) {
      return 'pump.loop.blocked.no_schedule';
    }
    final limits = await LoopLimits.load();
    if (!limits.isUsable) {
      return 'pump.loop.blocked.limits';
    }
    return null;
  }

  /// Switches to [mode]. Returns the blocking reason when nothing changed.
  Future<String?> setMode(PodLoopMode mode) async {
    if (mode == PodLoopMode.off) {
      await _turnOff();
      return null;
    }
    final blocked = await blockedReason();
    if (blocked != null) {
      return blocked;
    }
    await _store.clearLoopStop();
    await _store.saveLoopMode(mode);
    return null;
  }

  /// Stops automating, then hands the pod back to its own schedule.
  ///
  /// The cancel is best effort. A pod out of range cannot be told anything, and
  /// waiting for it would leave the switch stuck on while the user watches; the
  /// rate it is running expires by itself regardless.
  Future<void> _turnOff() async {
    await _store.saveLoopMode(PodLoopMode.off);
    await _store.clearLoopStop();
    if (_store.temporaryBasal == null) {
      return;
    }
    await controller.cancelTemporaryBasal();
  }
}
