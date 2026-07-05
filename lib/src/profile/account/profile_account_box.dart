import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/alert/loader_alert.dart';
import 'package:insulink/src/auth/auth_gate.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account.dart';

/// The signed-in account card shown at the top of the profile page: the stored
/// name (editable) plus a confirm-guarded log-out button.
class ProfileAccountBox extends StatefulWidget {
  const ProfileAccountBox({super.key});

  @override
  State<ProfileAccountBox> createState() => _ProfileAccountBoxState();
}

class _ProfileAccountBoxState extends State<ProfileAccountBox> {
  static const _storage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          _nameRow(theme),
          const SizedBox(height: 16),
          _logoutButton(theme),
        ],
      ),
    );
  }

  Widget _nameRow(ThemeData theme) {
    return FutureBuilder<String?>(
      future: _storage.read(key: "name"),
      builder: (context, snapshot) {
        final name = snapshot.data;
        return Row(
          children: [
            _avatar(theme, name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocaleText(
                    "profile.account.name",
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name ?? "-",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _editName(name),
              icon: const Icon(Icons.edit, size: 18),
              tooltip: Locales.string(context, "profile.account.save"),
            ),
          ],
        );
      },
    );
  }

  /// Circular badge showing the first letter of the stored name (or a person
  /// glyph when it is empty), tinted with the theme primary.
  Widget _avatar(ThemeData theme, String? name) {
    final initial = (name ?? "").trim();
    return CircleAvatar(
      radius: 24,
      backgroundColor: theme.colorScheme.primary,
      child: initial.isEmpty
          ? Icon(Icons.person, color: theme.colorScheme.onPrimary)
          : Text(
              initial[0].toUpperCase(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimary,
              ),
            ),
    );
  }

  Widget _logoutButton(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _confirmLogout,
        style: TextButton.styleFrom(
          foregroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        icon: const Icon(Icons.logout, size: 18),
        label: const LocaleText(
          "profile.account.logout",
          style: TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  void _editName(String? current) {
    final controller = TextEditingController(text: current);
    Alert(
      icon: CupertinoIcons.pencil,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            counterText: "",
            prefixIcon: const Icon(Icons.person),
            hintText: Locales.string(context, "profile.account.name"),
          ),
        ),
      ),
      cancelButton: true,
      confirmButtonText: "profile.account.save",
      callback: () => _submitName(controller.text.trim()),
    ).show(context);
  }

  Future<void> _submitName(String name) async {
    if (name.isEmpty) {
      return;
    }
    LoaderAlert().show(context);
    final renamed = await ProfileAccount().rename(context, name);
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    if (renamed) {
      setState(() {});
    }
  }

  void _confirmLogout() {
    Alert(
      description: "profile.account.logout_confirm",
      icon: CupertinoIcons.exclamationmark_triangle,
      cancelButton: true,
      confirmButtonText: "profile.account.logout",
      confirmButtonColor: Colors.redAccent,
      callback: _logout,
    ).show(context);
  }

  /// Logs out on the backend, clears the session, then returns to the auth gate
  /// (which shows the sign-in page).
  Future<void> _logout() async {
    LoaderAlert().show(context);
    await context.read<G7Controller>().disconnect();
    if (!mounted) {
      return;
    }
    await ProfileAccount().logout(context);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthGate()),
      (route) => false,
    );
  }
}
