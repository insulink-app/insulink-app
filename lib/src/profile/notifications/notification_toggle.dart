import 'package:flutter/material.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';

/// Settings toggle for one [NotificationSetting] (expiry, halftime, training …).
class NotificationToggle extends StatefulWidget {
  const NotificationToggle(this.setting, {super.key});

  final NotificationSetting setting;

  @override
  State<NotificationToggle> createState() => _NotificationToggleState();
}

class _NotificationToggleState extends State<NotificationToggle> {
  bool _enabled = true;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: widget.setting.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _enabled = snapshot.data ?? true;
        }
        return ProfileToggleRow(
          labelKey: widget.setting.labelKey,
          value: _enabled,
          onChanged: (value) async {
            await widget.setting.save(value);
            setState(() => _enabled = value);
          },
        );
      },
    );
  }
}
