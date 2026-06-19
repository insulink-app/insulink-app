import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/localization/locale_text.dart';

class ProfileNotificationToggle extends StatefulWidget {
  const ProfileNotificationToggle({super.key});

  @override
  State<ProfileNotificationToggle> createState() =>
      ProfileNotificationToggleState();
}

class ProfileNotificationToggleState extends State<ProfileNotificationToggle> {
  bool _notificationsEnabled = true;

  void _toggleNotifications(bool value) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: "notifications", value: value.toString());
    setState(() {
      _notificationsEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    const storage = FlutterSecureStorage();
    return FutureBuilder<String?>(
      future: storage.read(key: "notifications"),
      builder: (context, AsyncSnapshot<String?> notifications) {
        if (notifications.connectionState == ConnectionState.done) {
          _notificationsEnabled = notifications.data != "false";
        }
        return SwitchListTile(
          title: LocaleText("profile.notification.description"),
          value: _notificationsEnabled,
          onChanged: _toggleNotifications,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          inactiveThumbColor: Colors.grey,
        );
      },
    );
  }
}
