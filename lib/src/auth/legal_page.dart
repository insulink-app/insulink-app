import 'package:flutter/material.dart';
import 'package:insulink/src/auth/brand_mark.dart';
import 'package:insulink/src/auth/legal_consent_card.dart';
import 'package:insulink/src/base/page_primary_button.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/config/environment_options.dart';
import 'package:insulink/src/localization/locale_text.dart';
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

  /// Logo, title and subtitle centred in the free height, the consent card
  /// and the button at the foot; scrolls when the screen is too short.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Center(child: _intro())),
                    LegalConsentCard(
                      accepted: _accepted,
                      onChanged: (value) => setState(() => _accepted = value),
                      onOpenTerms: _openTerms,
                      onOpenPrivacy: _openPrivacyPolicy,
                    ),
                    const SizedBox(height: 14),
                    _continueButton(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro() {
    final colors = context.ink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const BrandMark(size: 60, framed: true),
        const SizedBox(height: 32),
        LocaleText(
          "legal.title",
          textAlign: TextAlign.center,
          style: InkText.bigValue.copyWith(fontSize: 38, height: 1.1),
        ),
        const SizedBox(height: 18),
        LocaleText(
          "legal.subtitle",
          textAlign: TextAlign.center,
          style: InkText.body.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: colors.muted,
          ),
        ),
      ],
    );
  }

  Widget _continueButton() {
    return PagePrimaryButton(
      onPressed: _accepted ? widget.onAccepted : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          LocaleText("legal.continue"),
          const Icon(PhosphorIconsBold.arrowRight, size: 22),
        ],
      ),
    );
  }
}
