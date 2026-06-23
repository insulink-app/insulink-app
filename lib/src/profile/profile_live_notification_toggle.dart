import 'package:flutter/material.dart';
import 'package:insulink/src/profile/profile_live_notification_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';

/// Settings toggle for the ongoing glucose notification (see
/// [ProfileLiveNotificationState]).
class ProfileLiveNotificationToggle extends StatefulWidget {
  const ProfileLiveNotificationToggle({super.key});

  @override
  State<ProfileLiveNotificationToggle> createState() =>
      _ProfileLiveNotificationToggleState();
}

class _ProfileLiveNotificationToggleState
    extends State<ProfileLiveNotificationToggle> {
  bool _enabled = true;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ProfileLiveNotificationState.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _enabled = snapshot.data ?? true;
        }
        return ProfileToggleRow(
          labelKey: "profile.live.description",
          value: _enabled,
          onChanged: (value) async {
            await ProfileLiveNotificationState.save(value);
            setState(() => _enabled = value);
          },
        );
      },
    );
  }
}
