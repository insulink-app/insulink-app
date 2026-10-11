import 'package:flutter/material.dart';
import 'package:insulink/main.dart';
import 'package:insulink/src/auth/auth_page.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Stands in for the account card in guest mode: says the data stays on this
/// device and offers signing in, which hands it all to the account.
class ProfileGuestBox extends StatelessWidget {
  const ProfileGuestBox({super.key});

  @override
  Widget build(BuildContext context) {
    return InkPanel.list(
      radius: InkRadius.tile,
      rows: [
        ListRow(
          icon: PhosphorIconsBold.cloudSlash,
          tone: ListRowTone.neutral,
          title: Locales.string(context, 'profile.account.guest_title'),
          subtitle: Locales.string(context, 'profile.account.guest_body'),
        ),
        ListRow(
          icon: PhosphorIconsBold.signIn,
          title: Locales.string(context, 'profile.account.sign_in'),
          trailing: Icon(
            PhosphorIconsBold.caretRight,
            size: 18,
            color: context.ink.muted,
          ),
          onTap: () => _signIn(context),
        ),
      ],
    );
  }

  /// Opens the sign-in page; once signed in, back to the app, rebuilt on the
  /// account's (and the handed-over) data.
  void _signIn(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AuthPage(
          onAuthenticated: () {
            navigator.popUntil((route) => route.isFirst);
            InsulinkApp.reload(navigator.context);
          },
        ),
      ),
    );
  }
}
