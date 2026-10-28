import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A small ⓘ that opens an explanation in an [InkSheet], titled [titleKey]
/// with the text of [bodyKey].
///
/// Settings pages show what can be set; why and how sits one tap away behind
/// this instead of as a paragraph between the controls (`docs/DESIGN.md`,
/// "Explanations"). Warnings and status messages are not explanations and
/// stay on the page.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.titleKey, required this.bodyKey});

  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: Locales.string(context, 'alert.explain'),
      constraints: const BoxConstraints.tightFor(
        width: InkSpace.minTouch,
        height: InkSpace.minTouch,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(PhosphorIconsRegular.info, size: 20),
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) {
    return showInkSheet<void>(
      context: context,
      builder: (_) => InkSheet(
        titleKey: titleKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: LocaleText(
            bodyKey,
            style: InkText.label.copyWith(fontSize: 15, height: 1.45),
          ),
        ),
      ),
    );
  }
}

/// A section heading with its [InfoButton] at the right end, for a group of
/// settings whose explanation used to stand under the heading.
class InfoHeading extends StatelessWidget {
  const InfoHeading({
    super.key,
    required this.labelKey,
    required this.bodyKey,
    this.style,
  });

  final String labelKey;
  final String bodyKey;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: LocaleText(labelKey, style: style)),
        InfoButton(titleKey: labelKey, bodyKey: bodyKey),
      ],
    );
  }
}
