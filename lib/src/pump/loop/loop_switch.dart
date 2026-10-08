import 'dart:async';

import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/pump/loop/loop_mode_backup.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';
import 'package:insulink/src/pump/pod_basal_adapter.dart';
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
  ///
  /// Puts the schedule on the pod first when the app has no record of one, so
  /// switching the automation on is one action again rather than two.
  Future<String?> setMode(PodLoopMode mode) async {
    if (mode == PodLoopMode.off) {
      await _turnOff();
      unawaited(ProfileSettings().push(null));
      return null;
    }
    if (_store.hasPod && _store.isActivated && _store.basalRates == null) {
      await _establishSchedule();
    }
    final blocked = await blockedReason();
    if (blocked != null) {
      return blocked;
    }
    await _store.clearLoopStop();
    await _store.saveLoopMode(mode);
    unawaited(ProfileSettings().push(null));
    return null;
  }

  /// Right after a pod is adopted from the account: puts the user's schedule on
  /// it, because a restore brings back the key but no record of what the pod
  /// runs, and switches the automation back on when it was on when the pod was
  /// last in use.
  ///
  /// Left alone while the pod's state is unknown or it is suspended: programming
  /// a schedule IS resuming, and a pause the user chose is not the app's to end.
  /// Engaging goes through [setMode], so every [blockedReason] check still
  /// applies. No second biometric: the user confirmed the automation when they
  /// first engaged it, and asked for it to come back on by itself.
  Future<void> resumeAfterRestore() async {
    if (controller.statusAge == null || controller.isSuspended) {
      return;
    }
    await _establishSchedule();
    if (await const LoopModeBackup().wasEngaged()) {
      await setMode(PodLoopMode.engaged);
    }
  }

  /// Puts the user's own profile on the pod when the app has no record of what
  /// the pod is running, and adopts it as that record.
  ///
  /// Sent rather than ASSUMED, and the difference is a dose. Every decision is
  /// anchored on the scheduled rate ([LoopAlgorithm.wantedUnitsPerHour] adds the
  /// correction to it), and the temporary rate the loop runs REPLACES the pod's
  /// schedule for as long as it lasts, so the anchor has to carry the background
  /// insulin itself. It also sets the base of every ceiling in [LoopSafety]. An
  /// anchor taken on faith is a dose taken on faith.
  ///
  /// Sending costs one command and makes it a fact. It goes through
  /// [PodController.applyBasalProfile], so the chokepoint that ends a running
  /// temporary rate first still applies, which is what a pod left mid-cycle by a
  /// previous install needs.
  ///
  /// Best effort: a failure leaves the rates unset, and [blockedReason] then says
  /// so rather than engaging on a schedule nobody established.
  Future<void> _establishSchedule() async {
    final profile = PodBasalAdapter((await ProfileBasalState.load()).active);
    if (!profile.isProgrammable) {
      return;
    }
    await controller.applyBasalProfile(profile.program);
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
