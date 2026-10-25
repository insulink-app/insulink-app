import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';

/// How each alarm feels on the Fitbit Air, coded like the alarm tones so it can
/// be told apart without looking: a double pulse means low, a single pulse
/// high; one group is the pre-warning, two the warning, three the urgent alarm.
///
/// The plugin offers exactly two primitives, one pulse (`tap`) and two pulses
/// (`vibrate`), each its own secure session of a few seconds. So the groups of
/// a pattern arrive several seconds apart, which is also what keeps them
/// countable on the wrist.
extension BandVibrationPattern on AlarmSlot {
  bool get doublePulse => switch (this) {
    AlarmSlot.lowWarning ||
    AlarmSlot.lowUrgent ||
    AlarmSlot.advisoryLow => true,
    AlarmSlot.highWarning ||
    AlarmSlot.highUrgent ||
    AlarmSlot.advisoryHigh => false,
  };

  int get pulseGroups => switch (this) {
    AlarmSlot.advisoryLow || AlarmSlot.advisoryHigh => 1,
    AlarmSlot.lowWarning || AlarmSlot.highWarning => 2,
    AlarmSlot.lowUrgent || AlarmSlot.highUrgent => 3,
  };

  /// Urgent alarms always ring the phone too, night mode or not.
  bool get urgent =>
      this == AlarmSlot.lowUrgent || this == AlarmSlot.highUrgent;

  /// Whether this alarm buzzes the band at all; each one on its own, default
  /// ON. Labelled like its tone slot.
  NotificationSetting get bandSetting =>
      NotificationSetting('band_vibration_$key', labelKey);
}
