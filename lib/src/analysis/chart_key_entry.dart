import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One entry of a chart's key: a rounded swatch and its muted label. A thin
/// swatch stands for a line, a thick one for a band.
class ChartKeyEntry extends StatelessWidget {
  const ChartKeyEntry({
    super.key,
    required this.color,
    required this.labelKey,
    this.thickness = 2.5,
  });

  final Color color;
  final String labelKey;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 7,
      children: [
        Container(
          width: 16,
          height: thickness,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(thickness < 5 ? 2 : 3),
          ),
        ),
        LocaleText(
          labelKey,
          style: InkText.label.copyWith(color: context.ink.muted),
        ),
      ],
    );
  }
}
