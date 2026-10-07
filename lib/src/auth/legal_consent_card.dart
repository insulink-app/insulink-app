import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The consent on the welcome page as a card: a 24 px checkbox in the accent
/// and "Ich akzeptiere die AGB und die Datenschutzerklärung." with both
/// documents as underlined links. A tap anywhere on the card ticks the box.
class LegalConsentCard extends StatelessWidget {
  const LegalConsentCard({
    super.key,
    required this.accepted,
    required this.onChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Material(
      color: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!accepted),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              _checkbox(colors),
              Expanded(child: _consentText(context, colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkbox(InsulinkColors colors) {
    return SizedBox.square(
      dimension: 24,
      child: Checkbox(
        value: accepted,
        onChanged: (value) => onChanged(value ?? false),
        activeColor: colors.accent,
        checkColor: colors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: colors.muted, width: 1.5),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _consentText(BuildContext context, InsulinkColors colors) {
    final plain = InkText.label.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: colors.muted,
    );
    final link = plain.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.accentText,
      decoration: TextDecoration.underline,
      decorationColor: colors.accentText,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: Locales.string(context, "legal.checkbox.prefix")),
          TextSpan(
            text: Locales.string(context, "legal.checkbox.terms"),
            style: link,
            recognizer: TapGestureRecognizer()..onTap = onOpenTerms,
          ),
          TextSpan(text: Locales.string(context, "legal.checkbox.and")),
          TextSpan(
            text: Locales.string(context, "legal.checkbox.privacy"),
            style: link,
            recognizer: TapGestureRecognizer()..onTap = onOpenPrivacy,
          ),
          TextSpan(text: Locales.string(context, "legal.checkbox.suffix")),
        ],
      ),
      style: plain,
    );
  }
}
