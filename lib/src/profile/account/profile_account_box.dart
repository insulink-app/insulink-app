import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/alert/alert.dart';
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_nameRow(theme), const SizedBox(height: 20), _logoutButton()],
      ),
    );
  }

  Widget _nameRow(ThemeData theme) {
    return FutureBuilder<String?>(
      future: _storage.read(key: "name"),
      builder: (context, snapshot) => Row(
        children: [
          const LocaleText("profile.account.name"),
          const Text(": "),
          Expanded(
            child: Text(
              snapshot.data ?? "-",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          GestureDetector(
            onTap: () => _editName(snapshot.data),
            child: Icon(Icons.edit, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return ElevatedButton.icon(
      onPressed: _confirmLogout,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: const Icon(Icons.logout, size: 20),
      label: const LocaleText(
        "profile.account.logout",
        style: TextStyle(color: Colors.white, fontSize: 15),
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
            border: const OutlineInputBorder(),
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
