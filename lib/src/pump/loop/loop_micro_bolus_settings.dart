import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';

/// The user's own settings for micro boluses, as editable profile settings.
///
/// Every number here makes the automation faster or slower to act, which is a
/// therapy choice and so belongs to the user. The defaults are the cautious end:
/// micro boluses off, half the missing insulin at most, half a unit at a time.
///
/// The bounds of each editor are the hard part. They are wide enough to tune to
/// a real person and narrow enough that no setting alone can make a dose the
/// other ceilings would not still clamp.
class LoopMicroBolusSettings {
  const LoopMicroBolusSettings._();

  /// Whether the automation may give micro boluses at all. OFF by default: it is
  /// the one setting that lets the automation put insulin into the body it can
  /// no longer take back, so it has to be chosen.
  static const enabled = NotificationSetting(
    'loop_micro_bolus_enabled',
    'profile.loop.micro_bolus.enabled',
    defaultValue: false,
  );

  /// Whether a micro bolus waits for a rising trend. With it off, a level or
  /// slowly falling glucose that is still predicted above target is corrected
  /// too.
  static const onlyRising = NotificationSetting(
    'loop_micro_bolus_only_rising',
    'profile.loop.micro_bolus.only_rising',
  );

  /// The largest single micro bolus, in tenths of a unit.
  static const maxUnits = NotificationThreshold(
    storageKey: 'loop_micro_bolus_max_tenths',
    labelKey: 'profile.loop.micro_bolus.max_units',
    valueKey: 'profile.loop.micro_bolus.max_units.value',
    defaultValue: 5,
    min: 1,
    max: 30,
    tenths: true,
  );

  /// The share of the missing insulin one micro bolus may give, in percent. The
  /// rest is left for the next cycle to decide on with a fresher reading.
  static const sharePercent = NotificationThreshold(
    storageKey: 'loop_micro_bolus_share_percent',
    labelKey: 'profile.loop.micro_bolus.share',
    valueKey: 'profile.loop.micro_bolus.share.value',
    defaultValue: 50,
    min: 10,
    max: 100,
    step: 10,
  );

  /// The glucose below which no micro bolus is given, however steep the rise.
  static const fromMgdl = NotificationThreshold(
    storageKey: 'loop_micro_bolus_from_mgdl',
    labelKey: 'profile.loop.micro_bolus.from',
    valueKey: 'profile.loop.micro_bolus.from.value',
    defaultValue: 140,
    min: 100,
    max: 250,
    step: 10,
  );

  /// The fewest minutes between two micro boluses. Five is every cycle.
  static const everyMinutes = NotificationThreshold(
    storageKey: 'loop_micro_bolus_every_minutes',
    labelKey: 'profile.loop.micro_bolus.every',
    valueKey: 'profile.loop.micro_bolus.every.value',
    defaultValue: 5,
    min: 5,
    max: 60,
    step: 5,
  );

  /// How long micro boluses pause after glucose reached the stop threshold.
  ///
  /// The rise after treating a low is sugar the user ate on purpose. Read as a
  /// rising trend it would be corrected straight back down into the next low.
  /// The upper bound is [LoopGlucose.lookback], the history the loop is handed.
  static const pauseAfterLow = NotificationThreshold(
    storageKey: 'loop_micro_bolus_pause_after_low_minutes',
    labelKey: 'profile.loop.micro_bolus.pause_after_low',
    valueKey: 'profile.loop.micro_bolus.pause_after_low.value',
    defaultValue: 90,
    min: 30,
    max: 180,
    step: 15,
  );

  /// The most insulin the automation may add within one hour while micro
  /// boluses are on, the rate's excess and the micro boluses together.
  ///
  /// Defaults to 2 U, below the rate ceiling, because this is the number that
  /// decides how much a sensor reading falsely high can put in within the hour
  /// (`docs/LOOP_MICRO_BOLUS.md`, "Measured").
  static const maxUnitsPerHour = NotificationThreshold(
    storageKey: 'loop_micro_bolus_max_per_hour',
    labelKey: 'profile.loop.micro_bolus.max_per_hour',
    valueKey: 'profile.loop.micro_bolus.max_per_hour.value',
    defaultValue: 2,
    min: 1,
    max: 10,
  );

  /// The longest a manual bolus waits for a running micro bolus to finish
  /// before it is sent, in seconds. Longer and it is refused with the time left,
  /// so the user is never left wondering whether their dose went out.
  ///
  /// The default covers a micro bolus of up to 1.5 U (2 s per 0.05 U).
  static const queueSeconds = NotificationThreshold(
    storageKey: 'loop_micro_bolus_queue_seconds',
    labelKey: 'profile.loop.micro_bolus.queue',
    valueKey: 'profile.loop.micro_bolus.queue.value',
    defaultValue: 60,
    min: 15,
    max: 180,
    step: 15,
  );

  static const toggles = [enabled, onlyRising];

  static const thresholds = [
    maxUnits,
    sharePercent,
    fromMgdl,
    everyMinutes,
    pauseAfterLow,
    maxUnitsPerHour,
    queueSeconds,
  ];
}
