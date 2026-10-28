import 'package:insulink/src/profile/notifications/notification_setting.dart';
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

  /// The target during the recovery after endurance. Only ever raises.
  static const recoveryTarget = NotificationThreshold(
    storageKey: 'activity_recovery_target_mgdl',
    labelKey: 'profile.activity_mode.recovery_target',
    valueKey: 'profile.activity_mode.recovery_target.value',
    defaultValue: 130,
    min: 100,
    max: 180,
    step: 10,
  );

  /// The share of the scheduled basal during the recovery. Never above 100 %:
  /// the recovery only ever takes insulin away.
  static const recoveryBasal = NotificationThreshold(
    storageKey: 'activity_recovery_basal_percent',
    labelKey: 'profile.activity_mode.recovery_basal',
    valueKey: 'profile.activity_mode.recovery_basal.value',
    defaultValue: 80,
    min: 50,
    max: 100,
    step: 10,
  );

  /// How long the recovery lasts after an endurance bout; 0 switches it off.
  static const recoveryHours = NotificationThreshold(
    storageKey: 'activity_recovery_hours',
    labelKey: 'profile.activity_mode.recovery_hours',
    valueKey: 'profile.activity_mode.recovery_hours.value',
    defaultValue: 6,
    min: 0,
    max: 12,
  );

  /// How much smaller the calculator's meal bolus is during the recovery after
  /// a long endurance bout; 0, the default, switches it off. A dose the user
  /// gives by hand is theirs to change, so it is never cut unasked.
  static const recoveryBolus = NotificationThreshold(
    storageKey: 'activity_recovery_bolus_percent',
    labelKey: 'profile.activity_mode.recovery_bolus',
    valueKey: 'profile.activity_mode.recovery_bolus.value',
    defaultValue: 0,
    min: 0,
    max: 50,
    step: 5,
  );

  /// How long an endurance bout must last before the meal bolus is cut after
  /// it. Longer than the recovery's own 20 minutes, so a ride to work or a walk
  /// to the shop leaves the next meal's dose alone.
  static const recoveryBolusMinutes = NotificationThreshold(
    storageKey: 'activity_recovery_bolus_minutes',
    labelKey: 'profile.activity_mode.recovery_bolus_minutes',
    valueKey: 'profile.activity_mode.recovery_bolus_minutes.value',
    defaultValue: 30,
    min: 20,
    max: 120,
    step: 5,
  );

  /// The pulse that, held for [ActivityPulseDetector.sustain], counts as
  /// endurance even when no walk or ride is detected (housework, a gym, a
  /// dance floor).
  static const pulseThreshold = NotificationThreshold(
    storageKey: 'activity_pulse_threshold_bpm',
    labelKey: 'profile.activity_mode.pulse_threshold',
    valueKey: 'profile.activity_mode.pulse_threshold.value',
    defaultValue: 110,
    min: 80,
    max: 160,
    step: 5,
  );

  /// Whether the activity mode is used at all. Off, the mode is always normal:
  /// no detection, workout or manual choice moves the loop.
  ///
  /// On by default, because switching it on is what the feature was built for;
  /// someone who finds the automatic change unsettling turns it off here.
  static const enabled = NotificationSetting(
    'activity_mode_enabled',
    'profile.activity_mode.enabled',
  );

  /// Whether the hand choice also sits on the overview, one tap away, for
  /// someone who switches modes often. Off by default: the profile is where a
  /// change to dosing is made, and the overview stays calm.
  static const onOverview = NotificationSetting(
    'activity_mode_on_overview',
    'profile.activity_mode.on_overview',
    defaultValue: false,
  );

  static const all = [
    enduranceTarget,
    enduranceBasal,
    strengthBasal,
    pulseThreshold,
    recoveryTarget,
    recoveryBasal,
    recoveryHours,
    recoveryBolus,
    recoveryBolusMinutes,
  ];
}
