import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One figure of a training, as the formatters write it ("2,32 km"): the
/// number large, the unit after the space small and muted, the label under
/// it, and optionally a muted glyph above. Shared by the live panel and the
/// training's detail page.
class CardioMetric extends StatelessWidget {
  const CardioMetric({
    super.key,
    required this.formatted,
    required this.labelKey,
    this.icon,
    this.size = 30,
  });

  final String formatted;
  final String labelKey;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final space = formatted.indexOf(' ');
    final value = space < 0 ? formatted : formatted.substring(0, space);
    final unit = space < 0 ? null : formatted.substring(space + 1);
    return Column(
      spacing: 4,
      children: [
        if (icon != null) Icon(icon, size: 20, color: colors.muted),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              text: value,
              style: InkText.bigValue.copyWith(fontSize: size),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: InkText.unit.copyWith(color: colors.muted),
                  ),
              ],
            ),
          ),
        ),
        Text(
          Locales.string(context, labelKey),
          style: InkText.label.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}

/// Figures side by side, parted by thin vertical lines.
class CardioMetricRow extends StatelessWidget {
  const CardioMetricRow({super.key, required this.metrics});

  final List<CardioMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final line = context.ink.line;
    return IntrinsicHeight(
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            if (index > 0) VerticalDivider(width: 1, thickness: 1, color: line),
            Expanded(child: metrics[index]),
          ],
        ],
      ),
    );
  }
}
