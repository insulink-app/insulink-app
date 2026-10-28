import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/band/band_test_button.dart';
import 'package:insulink/src/google_health/band/band_vibration_pattern.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_toggle.dart';

/// The Fitbit Air group of the notification settings: how the patterns are
/// coded, then one switch per alarm with a button that plays its pattern on
/// the band, then the battery warning.
class BandVibrationSettings extends StatelessWidget {
  const BandVibrationSettings({super.key});

  /// Low side first, each from pre-warning to urgent, so the pulse count
  /// grows down the list the way it grows on the wrist.
  static const _order = [
    AlarmSlot.advisoryLow,
    AlarmSlot.lowWarning,
    AlarmSlot.lowUrgent,
    AlarmSlot.advisoryHigh,
    AlarmSlot.highWarning,
    AlarmSlot.highUrgent,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        for (final slot in _order) _BandSlotRow(slot),
        const NotificationToggle(NotificationSetting.bandBatteryLow),
      ],
    );
  }
}

/// One alarm's switch with its preview button beside it.
class _BandSlotRow extends StatelessWidget {
  const _BandSlotRow(this.slot);

  final AlarmSlot slot;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 4,
      children: [
        Expanded(child: NotificationToggle(slot.bandSetting)),
        BandTestButton(slot: slot),
      ],
    );
  }
}
