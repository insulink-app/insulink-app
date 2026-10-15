import 'package:insulink/src/profile/notifications/notification_threshold.dart';

/// The three numbers behind the activity mode, as editable settings.
///
/// Endurance moves both inputs of the loop's arithmetic: the target it aims at
/// and the share of the scheduled basal it anchors on. Strength only moves the
/// anchor, because raising the target is exactly the wrong answer to a glucose
/// that climbs during the set.
///
/// ponytail: reuses [NotificationThreshold] like [LoopSettings], whole numbers
/// in 10 steps. A percentage is something a user can reason about; "73 %" is
/// not a decision anyone makes.
class ActivityModeSettings {
  const ActivityModeSettings._();

  /// The target the loop aims at during endurance. Only ever raises the user's
  /// own target, see [ActivityModeAdjustment.limits].
  static const enduranceTarget = NotificationThreshold(
    storageKey: 'activity_endurance_target_mgdl',
    labelKey: 'profile.activity_mode.endurance_target',
    valueKey: 'profile.activity_mode.endurance_target.value',
    defaultValue: 150,
    min: 100,
    max: 200,
    step: 10,
  );

  /// The share of the scheduled basal the loop anchors on during endurance.
  static const enduranceBasal = NotificationThreshold(
    storageKey: 'activity_endurance_basal_percent',
    labelKey: 'profile.activity_mode.endurance_basal',
    valueKey: 'profile.activity_mode.endurance_basal.value',
    defaultValue: 50,
    min: 0,
    max: 100,
    step: 10,
  );

  /// The share of the scheduled basal the loop anchors on during strength.
  ///
  /// Capped at 150 %. Everything above 100 % is insulin above the schedule, so
  /// [LoopSafety] counts it as a dose and every ceiling still holds it.
  static const strengthBasal = NotificationThreshold(
    storageKey: 'activity_strength_basal_percent',
    labelKey: 'profile.activity_mode.strength_basal',
    valueKey: 'profile.activity_mode.strength_basal.value',
    defaultValue: 120,
    min: 80,
    max: 150,
    step: 10,
  );

  static const all = [enduranceTarget, enduranceBasal, strengthBasal];
}
