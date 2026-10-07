import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The full-width primary button at the foot of an onboarding or sign-in
/// page: 58 px high, fully round, label 17/700 in the colour on the accent.
/// While it cannot act it stays in the accent at 35 %, so it still reads as
/// the way on rather than as a grey control.
class PagePrimaryButton extends StatelessWidget {
  const PagePrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(58),
        shape: const StadiumBorder(),
        textStyle: InkText.button.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        disabledBackgroundColor: colors.accent.withValues(alpha: 0.35),
        disabledForegroundColor: colors.onAccent,
      ),
      child: child,
    );
  }
}
