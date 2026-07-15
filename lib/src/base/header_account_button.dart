import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/profile_page.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class HeaderAccountButton extends StatefulWidget
    implements PreferredSizeWidget {
  const HeaderAccountButton({super.key});

  @override
  State<HeaderAccountButton> createState() => _HeaderAccountButtonState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _HeaderAccountButtonState extends State<HeaderAccountButton> {
  static const _storage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _avatar(Theme.of(context)),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ProfilePage()),
        );
      },
    );
  }

  /// Circular badge showing the first letter of the stored name (or a person
  /// glyph when it is empty), matching the profile account box avatar.
  Widget _avatar(ThemeData theme) {
    return FutureBuilder<String?>(
      future: _storage.read(key: "name"),
      builder: (context, snapshot) {
        final initial = (snapshot.data ?? "").trim();
        return CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primary,
          child: initial.isEmpty
              ? Icon(
                  PhosphorIconsRegular.user,
                  color: theme.colorScheme.onPrimary,
                )
              : Text(
                  initial[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
        );
      },
    );
  }
}
