import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// "− 16 +" in a pill in the page colour: two round 44 px buttons around the
/// count. A button that cannot act ([onMinus] or [onPlus] null) is dimmed.
class StepperPill extends StatelessWidget {
  const StepperPill({
    super.key,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    required this.minusLabelKey,
    required this.plusLabelKey,
  });

  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  /// Read out by screen readers for the two buttons.
  final String minusLabelKey;
  final String plusLabelKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: colors.ground,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            context,
            colors,
            PhosphorIconsBold.minus,
            minusLabelKey,
            onMinus,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: InkText.rowTitle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _button(
            context,
            colors,
            PhosphorIconsBold.plus,
            plusLabelKey,
            onPlus,
          ),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context,
    InsulinkColors colors,
    IconData icon,
    String labelKey,
    VoidCallback? onTap,
  ) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: Locales.string(context, labelKey),
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: colors.panelRaised,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: InkSpace.minTouch,
              child: Icon(icon, size: 18, color: colors.text),
            ),
          ),
        ),
      ),
    );
  }
}
