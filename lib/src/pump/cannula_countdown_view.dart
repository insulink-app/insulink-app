import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_activation_page.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:provider/provider.dart';

/// The seconds left before the cannula fires, large in place of the stage text
/// while [CannulaConfirmation] counts down; [orElse] the rest of the time.
class CannulaCountdownView extends StatelessWidget {
  const CannulaCountdownView({super.key, required this.orElse});

  final Widget orElse;

  @override
  Widget build(BuildContext context) {
    final secondsLeft = context.watch<CannulaConfirmation>().secondsLeft;
    if (secondsLeft == null) {
      return orElse;
    }
    return Column(
      children: [
        const SizedBox(height: 32),
        LocaleText(
          'pump.activate.countdown_title',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          '$secondsLeft',
          style: InkText.bigValue.copyWith(
            fontSize: 96,
            color: context.ink.accent,
          ),
        ),
        const SizedBox(height: 16),
        LocaleText(
          'pump.activate.countdown_body',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.ink.muted),
        ),
      ],
    );
  }
}
