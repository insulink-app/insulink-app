import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/base/measurement_row.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The weight at the top of the page, open without a card: "Aktuell" over the
/// latest value large, the change since the entry before on the right, and
/// the BMI as a pill underneath when a height is stored.
class WeightCurrentCard extends StatelessWidget {
  const WeightCurrentCard({
    super.key,
    required this.latest,
    required this.previousKg,
    this.bmi,
  });

  final WeightEntry latest;
  final double? previousKg;

  /// Body-mass index (from the stored height), shown as a pill when available.
  final double? bmi;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final delta = previousKg == null ? null : latest.kg - previousKg!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            'sport.weight.current',
            style: InkText.label.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                sportDecimal(latest.kg, 1),
                style: InkText.bigValue.copyWith(
                  fontSize: 56,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 8),
              Text('kg', style: InkText.section.copyWith(color: colors.muted)),
              const Spacer(),
              if (delta != null && delta != 0)
                MeasurementDeltaChip(delta: delta, unit: 'kg'),
            ],
          ),
          if (bmi != null) ...[
            const SizedBox(height: 12),
            _bmiPill(context, colors),
          ],
        ],
      ),
    );
  }

  Widget _bmiPill(BuildContext context, InsulinkColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        color: colors.accentSoft,
        shape: const StadiumBorder(),
      ),
      child: Text(
        '${Locales.string(context, 'sport.weight.bmi')} ${sportDecimal(bmi!, 1)}',
        style: InkText.label.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.accentText,
        ),
      ),
    );
  }
}
