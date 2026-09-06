import 'package:flutter/material.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';

/// Settings toggle for one [NotificationSetting] (expiry, halftime, training …).
class NotificationToggle extends StatefulWidget {
  const NotificationToggle(this.setting, {super.key, this.onApplied});

  final NotificationSetting setting;

  /// Run after the new value is stored, for a setting that something has to act
  /// on rather than merely read later. Most of these are read fresh wherever
  /// they matter and need nothing; the lock-screen style has to restart the
  /// service (see [ProfileLockscreenToggle]).
  final Future<void> Function()? onApplied;

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
            if (mounted) {
              setState(() => _enabled = value);
            }
            await widget.onApplied?.call();
          },
        );
      },
    );
  }
}
