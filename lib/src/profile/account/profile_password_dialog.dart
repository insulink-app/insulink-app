import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/alert/loader_alert.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Current + new password prompt that forwards the change to the backend. The
/// password is never stored on device. Shown from the account card.
class ProfilePasswordDialog {
  const ProfilePasswordDialog();

  void show(BuildContext context) {
    final current = TextEditingController();
    final next = TextEditingController();
    Alert(
      icon: PhosphorIconsRegular.lock,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: _PasswordFields(current: current, next: next),
      ),
      cancelButton: true,
      confirmButtonText: "profile.account.save",
      callback: () => _submit(context, current.text, next.text),
    ).show(context);
  }

  Future<void> _submit(
    BuildContext context,
    String current,
    String next,
  ) async {
    if (current.isEmpty || next.isEmpty) {
      return;
    }
    LoaderAlert().show(context);
    final changed = await ProfileAccount().changePassword(
      context,
      current,
      next,
    );
    if (!context.mounted) {
      return;
    }
    Navigator.pop(context);
    Alert(
      type: changed ? AlertType.success : AlertType.error,
      description: changed
          ? "profile.account.password_changed"
          : "profile.account.password_error",
    ).show(context);
  }
}

/// The two obscured password fields with a shared show/hide toggle. Stateful
/// only for the toggle; the controllers are owned by [ProfilePasswordDialog] so
/// its confirm callback can still read the entered text.
class _PasswordFields extends StatefulWidget {
  const _PasswordFields({required this.current, required this.next});

  final TextEditingController current;
  final TextEditingController next;

  @override
  State<_PasswordFields> createState() => _PasswordFieldsState();
}

class _PasswordFieldsState extends State<_PasswordFields> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(widget.current, "profile.account.current_password", true),
        const SizedBox(height: 12),
        _field(widget.next, "profile.account.new_password", false),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String hintKey,
    bool autofocus,
  ) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        prefixIcon: const Icon(PhosphorIconsRegular.lock),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
          tooltip: Locales.string(context, "profile.account.show_password"),
        ),
        hintText: Locales.string(context, hintKey),
      ),
    );
  }
}
