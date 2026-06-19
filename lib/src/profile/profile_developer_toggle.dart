import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_developer_state.dart';
import 'package:provider/provider.dart';

class ProfileDeveloperToggle extends StatelessWidget {
  const ProfileDeveloperToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final developer = context.watch<ProfileDeveloperState>();
    return SwitchListTile(
      title: LocaleText("profile.developer.description"),
      value: developer.enabled,
      onChanged: developer.setEnabled,
      activeThumbColor: Theme.of(context).colorScheme.primary,
      inactiveThumbColor: Colors.grey,
    );
  }
}
