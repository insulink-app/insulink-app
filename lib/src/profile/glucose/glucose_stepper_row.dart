import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One labelled value with – / + buttons that step by the configured mg/dL step.
class GlucoseStepperRow extends StatelessWidget {
  const GlucoseStepperRow({
    super.key,
    required this.labelKey,
    required this.valueText,
    required this.accent,
    required this.onMinus,
    required this.onPlus,
    this.valueChild,
  });

  final String labelKey;
  final String valueText;
  final Color accent;
  final VoidCallback onMinus, onPlus;

  /// Optional: replaces the value text (e.g. with an inline-editable field). It
  /// then manages its own width; otherwise [valueText] is a fixed 96px wide.
  final Widget? valueChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: _label(theme)),
        CircleIconButton(
          icon: PhosphorIconsRegular.minus,
          accent: accent,
          onTap: onMinus,
        ),
        const SizedBox(width: 10),
        _value(),
        const SizedBox(width: 10),
        CircleIconButton(
          icon: PhosphorIconsRegular.plus,
          accent: accent,
          onTap: onPlus,
        ),
      ],
    );
  }

  Widget _label(ThemeData theme) {
    return LocaleText(
      labelKey,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _value() {
    if (valueChild != null) {
      return valueChild!;
    }
    return SizedBox(
      width: 96,
      child: Text(
        valueText,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}
