import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/config/environment_options.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// First-launch screen: the user must accept the terms and privacy policy
/// before anything else. Persisted via [onAccepted] so it only ever shows once.
class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  bool _accepted = false;

  String get _domain => EnvironmentOptions.environment.domain;

  void _openTerms() {
    launchUrl(Uri.parse("https://$_domain/terms-of-service/"));
  }

  void _openPrivacyPolicy() {
    launchUrl(Uri.parse("https://$_domain/privacy-policy/"));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_intro(theme), _actions(theme)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        Center(
          child: Image.asset(
            theme.brightness == Brightness.light
                ? 'assets/images/logo-black.png'
                : 'assets/images/logo-white.png',
            width: 100,
          ),
        ),
        const SizedBox(height: 28),
        LocaleText(
          "legal.title",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        LocaleText(
          "legal.subtitle",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _actions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _consentRow(theme),
          const SizedBox(height: 16),
          _continueButton(theme),
        ],
      ),
    );
  }

  Widget _consentRow(ThemeData theme) {
    return GestureDetector(
      onTap: () => setState(() => _accepted = !_accepted),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _accepted,
              onChanged: (value) => setState(() => _accepted = value ?? false),
              activeColor: theme.colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              side: BorderSide(
                color: theme.colorScheme.onSurfaceVariant,
                width: 1.5,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _consentText(theme)),
        ],
      ),
    );
  }

  Widget _consentText(ThemeData theme) {
    final plain = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final link = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: Locales.string(context, "legal.checkbox.prefix"),
            style: plain,
          ),
          TextSpan(
            text: Locales.string(context, "legal.checkbox.terms"),
            style: link,
            recognizer: TapGestureRecognizer()..onTap = _openTerms,
          ),
          TextSpan(
            text: Locales.string(context, "legal.checkbox.and"),
            style: plain,
          ),
          TextSpan(
            text: Locales.string(context, "legal.checkbox.privacy"),
            style: link,
            recognizer: TapGestureRecognizer()..onTap = _openPrivacyPolicy,
          ),
        ],
      ),
    );
  }

  Widget _continueButton(ThemeData theme) {
    return ElevatedButton.icon(
      onPressed: _accepted ? widget.onAccepted : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(
          _accepted
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 16),
        ),
        minimumSize: WidgetStateProperty.all(const Size(double.infinity, 0)),
      ),
      icon: Icon(
        PhosphorIconsBold.arrowRight,
        color: theme.colorScheme.onPrimary,
        size: 25,
      ),
      label: LocaleText(
        "legal.continue",
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
