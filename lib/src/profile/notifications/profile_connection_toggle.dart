import 'package:flutter/material.dart';
import 'package:insulink/src/profile/notifications/profile_connection_state.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';

/// Settings toggle for the "connection lost" warning (see [ProfileConnectionState]).
class ProfileConnectionToggle extends StatefulWidget {
  const ProfileConnectionToggle({super.key});

  @override
  State<ProfileConnectionToggle> createState() =>
      _ProfileConnectionToggleState();
}

class _ProfileConnectionToggleState extends State<ProfileConnectionToggle> {
  final ProfileConnectionState _state = ProfileConnectionState();
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
          labelKey: "profile.connection.description",
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
