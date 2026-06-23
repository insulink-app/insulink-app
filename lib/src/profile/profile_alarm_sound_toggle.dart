import 'package:flutter/material.dart';
import 'package:insulink/src/profile/profile_alarm_sound_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';

/// Settings toggle for the audible alarm tone (see [ProfileAlarmSoundState]).
class ProfileAlarmSoundToggle extends StatefulWidget {
  const ProfileAlarmSoundToggle({super.key});

  @override
  State<ProfileAlarmSoundToggle> createState() =>
      _ProfileAlarmSoundToggleState();
}

class _ProfileAlarmSoundToggleState extends State<ProfileAlarmSoundToggle> {
  final ProfileAlarmSoundState _state = ProfileAlarmSoundState();
  bool _enabled = true;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _state.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _enabled = snapshot.data ?? true;
        }
        return ProfileToggleRow(
          labelKey: "profile.alarmsound.description",
          value: _enabled,
          onChanged: (value) async {
            await _state.save(value);
            setState(() => _enabled = value);
          },
        );
      },
    );
  }
}
