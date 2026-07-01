import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// One labelled value with – / + buttons that step by the configured mg/dL step.
class GlucoseStepperRow extends StatelessWidget {
  const GlucoseStepperRow({
    super.key,
    required this.labelKey,
    required this.valueText,
    required this.accent,
    required this.onMinus,
    required this.onPlus,
    this.onValueTap,
  });

  final String labelKey;
  final String valueText;
  final Color accent;
  final VoidCallback onMinus, onPlus;

  /// Optional: tippt man auf den Wert, direkte Zahleneingabe (statt nur +/-).
  final VoidCallback? onValueTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: _label(theme)),
        CircleIconButton(icon: Icons.remove, accent: accent, onTap: onMinus),
        _value(),
        CircleIconButton(icon: Icons.add, accent: accent, onTap: onPlus),
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
    final text = Text(
      valueText,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
    return SizedBox(
      width: 96,
      child: onValueTap == null
          ? text
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onValueTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: text,
              ),
            ),
    );
  }
}
