import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A form field with its label above it, the field filled with the panel
/// colour and a faint rim, as a field stands on the page rather than in a
/// sheet. Wraps any field or dropdown; the look comes in through the theme.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.labelKey,
    required this.child,
    this.fill,
  });

  final String labelKey;
  final Widget child;

  /// The field's fill; the panel colour on a page, the page colour inside a
  /// sheet (whose own face is the panel colour).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final theme = Theme.of(context);
    OutlineInputBorder rim(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(InkRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: LocaleText(
            labelKey,
            style: InkText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.muted,
            ),
          ),
        ),
        Theme(
          data: theme.copyWith(
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              fillColor: fill ?? colors.panel,
              enabledBorder: rim(colors.border, 1),
              border: rim(colors.border, 1),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}
