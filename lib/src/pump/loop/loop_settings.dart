import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/pump/loop/loop_limits.dart';

/// The three numbers the automation is bounded by, as editable settings.
///
/// Everything else the loop needs is already tuned elsewhere: the correction
/// factor and insulin duration on the bolus profile, the target on the glucose
/// profile. Only these three are the automation's own.
///
/// ponytail: reuses [NotificationThreshold], which despite its name is the
/// generic "an integer with editor bounds, stored under a key" primitive the
/// profile already renders with [SettingValueCard]. Whole units on purpose:
/// these are ceilings, not doses, and a ceiling of "3 U/h" is a number a user
/// can reason about where "2.85 U/h" is not.
class LoopSettings {
  const LoopSettings._();

  /// Glucose at which the automation stops adding insulin.
  ///
  /// Capped below a normal target so the ceiling itself cannot be dragged up
  /// into the range the loop is supposed to aim for. A target set lower than
  /// this is still possible, and [LoopLimits.problem] catches that pair rather
  /// than letting the loop run on limits that contradict each other.
  static const suspendBelow = NotificationThreshold(
    storageKey: LoopLimits.keySuspendBelow,
    labelKey: 'profile.loop.suspend_below',
    valueKey: 'profile.loop.suspend_below.value',
    defaultValue: LoopLimits.defaultSuspendBelowMgdl,
    min: LoopLimits.minSuspendBelowMgdl,
    max: 100,
    step: 5,
  );

  /// The most the automation may ever run the basal rate at.
  static const maxRate = NotificationThreshold(
    storageKey: LoopLimits.keyMaxRate,
    labelKey: 'profile.loop.max_rate',
    valueKey: 'profile.loop.max_rate.value',
    defaultValue: 3,
    min: 1,
    max: 10,
  );

  /// The most insulin the automation will let stand on board before it stops
  /// adding to it.
  static const maxIob = NotificationThreshold(
    storageKey: LoopLimits.keyMaxIob,
    labelKey: 'profile.loop.max_iob',
    valueKey: 'profile.loop.max_iob.value',
    defaultValue: 5,
    min: 1,
    max: 15,
  );

  static const all = [suspendBelow, maxRate, maxIob];
}
