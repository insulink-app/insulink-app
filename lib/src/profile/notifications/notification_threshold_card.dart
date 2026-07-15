import 'package:flutter/material.dart';
import 'package:insulink/src/base/setting_value_card.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';

/// Settings card for one [NotificationThreshold] (pod expiry hours, pod units
/// left …). Loads the stored value the same way [NotificationToggle] loads its
/// flag, and hands the editing to the shared [SettingValueCard].
class NotificationThresholdCard extends StatefulWidget {
  const NotificationThresholdCard(this.threshold, {super.key});

  final NotificationThreshold threshold;

  @override
  State<NotificationThresholdCard> createState() =>
      _NotificationThresholdCardState();
}

class _NotificationThresholdCardState extends State<NotificationThresholdCard> {
  late int _value = widget.threshold.defaultValue;

  @override
  Widget build(BuildContext context) {
    final threshold = widget.threshold;
    return FutureBuilder<int>(
      future: threshold.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _value = snapshot.data ?? threshold.defaultValue;
        }
        return SettingValueCard(
          labelKey: threshold.labelKey,
          valueKey: threshold.valueKey,
          value: _value,
          min: threshold.min,
          max: threshold.max,
          step: threshold.step,
          onChanged: _save,
        );
      },
    );
  }

  Future<void> _save(int value) async {
    await widget.threshold.save(value);
    setState(() => _value = value);
  }
}
