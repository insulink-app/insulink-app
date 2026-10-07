import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/alert/loader_alert.dart';
import 'package:insulink/src/auth/auth_gate.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account.dart';
import 'package:insulink/src/profile/account/profile_password_dialog.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

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
    return InkPanel.list(
      radius: InkRadius.tile,
      rows: [
        Padding(padding: const EdgeInsets.all(16), child: _nameRow(theme)),
        _actionButton(
          icon: PhosphorIconsBold.lock,
          labelKey: "profile.account.change_password",
          onPressed: () => const ProfilePasswordDialog().show(context),
          chevron: true,
        ),
        _actionButton(
          icon: PhosphorIconsBold.signOut,
          labelKey: "profile.account.logout",
          onPressed: _confirmLogout,
          color: context.danger,
        ),
      ],
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
                    style: InkText.caption.copyWith(color: context.ink.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name ?? "-",
                    overflow: TextOverflow.ellipsis,
                    style: InkText.bigValue.copyWith(fontSize: 20),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _editName(name),
              icon: const Icon(PhosphorIconsBold.pencilSimple, size: 18),
              tooltip: Locales.string(context, "profile.account.save"),
            ),
          ],
        );
      },
    );
  }

  /// 56 px accent badge with the first letter of the stored name in the
  /// colour on the accent (or a person glyph when it is empty).
  Widget _avatar(ThemeData theme, String? name) {
    final colors = context.ink;
    final initial = (name ?? "").trim();
    return CircleAvatar(
      radius: 28,
      backgroundColor: colors.accent,
      child: initial.isEmpty
          ? Icon(PhosphorIconsBold.user, color: colors.onAccent)
          : Text(
              initial[0].toUpperCase(),
              style: InkText.bigValue.copyWith(
                fontSize: 24,
                color: colors.onAccent,
              ),
            ),
    );
  }

  /// One action row of the panel (change password / log out): the bare icon,
  /// the label, and a chevron where it opens something. The panel draws the
  /// lines between the rows.
  Widget _actionButton({
    required IconData icon,
    required String labelKey,
    required VoidCallback onPressed,
    Color? color,
    bool chevron = false,
  }) {
    final colors = context.ink;
    final tone = color ?? colors.text;
    return InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            spacing: 14,
            children: [
              Icon(icon, size: 20, color: tone),
              Expanded(
                child: LocaleText(
                  labelKey,
                  style: InkText.row.copyWith(color: tone),
                ),
              ),
              if (chevron)
                Icon(
                  PhosphorIconsBold.caretRight,
                  size: 18,
                  color: colors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _editName(String? current) {
    final controller = TextEditingController(text: current);
    Alert(
      icon: PhosphorIconsBold.pencilSimple,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            counterText: "",
            prefixIcon: const Icon(PhosphorIconsBold.user),
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

  /// Names the one thing a sign-out does NOT take with it, when there is one.
  ///
  /// A user about to sign out with a pod on their body needs to know it stays
  /// paired and stays delivering: the alternative reading, that signing out also
  /// gets rid of the pod, would be a dangerous thing to believe.
  void _confirmLogout() {
    final hasPod = context.read<PodController>().hasPod;
    Alert(
      description: hasPod
          ? "profile.account.logout_keeps_pod"
          : "profile.account.logout_confirm",
      icon: PhosphorIconsBold.warning,
      cancelButton: true,
      confirmButtonText: "profile.account.logout",
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: _logout,
    ).show(context);
  }

  /// Logs out on the backend, clears the session, then returns to the auth gate
  /// (which shows the sign-in page).
  Future<void> _logout() async {
    LoaderAlert().show(context);
    await context.read<CgmController>().disconnect();
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
