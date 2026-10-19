import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/alert/loader_alert.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Asks for the password before the account and all of its data are deleted
/// for good. The password is what makes this the owner's decision: a phone
/// left unlocked, or a stolen session, cannot wipe someone's history.
class ProfileDeleteDialog {
  const ProfileDeleteDialog();

  /// [onDeleted] runs once the account is gone, to leave the signed-in app.
  void show(BuildContext context, Future<void> Function() onDeleted) {
    final password = TextEditingController();
    Alert(
      icon: PhosphorIconsBold.trash,
      description: "profile.account.delete_confirm",
      content: TextField(
        controller: password,
        autofocus: true,
        obscureText: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          prefixIcon: const Icon(PhosphorIconsBold.lock),
          hintText: Locales.string(context, "profile.account.current_password"),
        ),
      ),
      cancelButton: true,
      confirmButtonText: "profile.account.delete_button",
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: () => _submit(context, password.text, onDeleted),
    ).show(context);
  }

  Future<void> _submit(
    BuildContext context,
    String password,
    Future<void> Function() onDeleted,
  ) async {
    if (password.isEmpty) {
      return;
    }
    LoaderAlert().show(context);
    final deleted = await ProfileAccount().delete(context, password);
    if (!context.mounted) {
      return;
    }
    Navigator.pop(context);
    if (deleted) {
      await onDeleted();
      return;
    }
    Alert(
      type: AlertType.error,
      description: "profile.account.delete_error",
    ).show(context);
  }
}
