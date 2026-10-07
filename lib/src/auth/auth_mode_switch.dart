import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The switch at the foot of the sign-in page: "Noch kein Konto? Registrieren"
/// (or back to signing in), the second half as the bold link.
class AuthModeSwitch extends StatelessWidget {
  const AuthModeSwitch({
    super.key,
    required this.signUp,
    required this.onPressed,
  });

  /// Whether the page is in sign-up mode; the switch offers the other one.
  final bool signUp;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final key = signUp ? 'auth.to_signin' : 'auth.to_signup';
    final style = InkText.body.copyWith(
      fontWeight: FontWeight.w400,
      color: colors.muted,
    );
    return TextButton(
      onPressed: onPressed,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: '${Locales.string(context, '$key.prefix')} '),
            TextSpan(
              text: Locales.string(context, '$key.link'),
              style: style.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.accentText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
