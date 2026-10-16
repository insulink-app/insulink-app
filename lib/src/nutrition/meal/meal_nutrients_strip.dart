import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The meal's other nutrients under the carbs / glucose / bolus strip:
/// protein, and fat and energy when the entries know them (products and photo
/// estimates logged since they are kept). Read only; they follow the entries.
class MealNutrientsStrip extends StatelessWidget {
  const MealNutrientsStrip({super.key, required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final fat = meal.fat;
    final kcal = meal.kcal;
    final cells = [
      _cell(
        colors,
        'nutrition.food.protein',
        sportDecimal(meal.protein, 0),
        'g',
      ),
      if (fat != null)
        _cell(colors, 'nutrition.food.fat', sportDecimal(fat, 0), 'g'),
      if (kcal != null)
        _cell(colors, 'nutrition.food.energy', sportDecimal(kcal, 0), 'kcal'),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(InkRadius.panel),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var index = 0; index < cells.length; index++) ...[
              if (index > 0)
                VerticalDivider(width: 1, thickness: 1, color: colors.line),
              Expanded(child: cells[index]),
            ],
          ],
        ),
      ),
    );
  }

  /// A small muted label over the value with its unit.
  Widget _cell(
    InsulinkColors colors,
    String labelKey,
    String value,
    String unit,
  ) {
    return Column(
      spacing: 4,
      children: [
        LocaleText(
          labelKey,
          style: InkText.caption.copyWith(color: colors.muted),
        ),
        Text.rich(
          TextSpan(
            text: value,
            style: InkText.rowTitle.copyWith(fontSize: 17),
            children: [
              TextSpan(
                text: ' $unit',
                style: InkText.label.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
