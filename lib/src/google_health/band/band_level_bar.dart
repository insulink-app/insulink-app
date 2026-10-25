import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One reading of the band as a labelled bar, drawn like the pod's reservoir
/// and lifetime bars so the device pages read as one design: muted label left,
/// an optional muted note and the bold value right, a 6 px bar under them that
/// turns amber once the reading needs a look.
class BandLevelBar extends StatelessWidget {
  const BandLevelBar({
    super.key,
    required this.labelKey,
    required this.value,
    required this.fraction,
    this.note,
    this.warn = false,
  });

  final String labelKey;
  final String value;
  final double fraction;

  /// A muted line beside the value, such as the battery's time left.
  final String? note;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 10,
          children: [
            Text(
              Locales.string(context, labelKey),
              style: InkText.label.copyWith(color: colors.muted),
            ),
            const Spacer(),
            if (note case final note?)
              Text(note, style: InkText.label.copyWith(color: colors.muted)),
            Text(
              value,
              style: InkText.row.copyWith(
                fontWeight: FontWeight.w700,
                color: warn ? colors.high : colors.text,
              ),
            ),
          ],
        ),
        LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          color: warn ? colors.high : colors.accent,
          backgroundColor: colors.line,
        ),
      ],
    );
  }
}
