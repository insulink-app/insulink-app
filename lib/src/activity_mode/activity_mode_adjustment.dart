import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/activity_mode/activity_mode_store.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';

/// What the activity mode changes about one automated cycle.
///
/// Only two inputs of [LoopAlgorithm] move: the target it corrects towards and
/// the scheduled rate it anchors on. [LoopSafety] keeps measuring every ceiling
/// against the user's real schedule, so the basal strength adds above it counts
/// as a dose like any correction, and nothing here can lift a limit.
class ActivityModeAdjustment {
  const ActivityModeAdjustment({
    required this.mode,
    this.targetMgdl,
    this.basalPercent = 100,
  });

  const ActivityModeAdjustment.none()
    : mode = ActivityMode.normal,
      targetMgdl = null,
      basalPercent = 100;

  /// Reads the mode in force and its settings. The default reader of
  /// [PodLoopRunner].
  static Future<ActivityModeAdjustment> load(DateTime now) async {
    final reading = await const ActivityModeStore().current(now);
    return switch (reading.mode) {
      ActivityMode.normal => const ActivityModeAdjustment.none(),
      ActivityMode.endurance => ActivityModeAdjustment(
        mode: ActivityMode.endurance,
        targetMgdl: await ActivityModeSettings.enduranceTarget.load(),
        basalPercent: await ActivityModeSettings.enduranceBasal.load(),
      ),
      ActivityMode.strength => ActivityModeAdjustment(
        mode: ActivityMode.strength,
        basalPercent: await ActivityModeSettings.strengthBasal.load(),
      ),
    };
  }

  final ActivityMode mode;
  final int? targetMgdl;
  final int basalPercent;

  /// The limits with the mode's target. Only ever raises the user's own, so a
  /// user whose everyday target is already higher is never dosed harder for
  /// going for a walk.
  LoopLimits limits(LoopLimits base) {
    final target = targetMgdl;
    if (target == null || target <= base.targetMgdl) {
      return base;
    }
    return base.withTarget(target);
  }

  /// The scheduled rate scaled by the mode, which the arithmetic anchors on.
  double anchor(double scheduledUnitsPerHour) =>
      scheduledUnitsPerHour * basalPercent / 100;
}
