import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Opens the nutrients of one photo-estimated [entry] for correction. Every
/// edit goes straight to [onChanged]; the photo is a guess, so each figure can
/// be typed over.
Future<void> showMealEntryNutrients(
  BuildContext context,
  MealEntry entry,
  ValueChanged<MealEntry> onChanged,
) {
  return showInkSheet(
    context: context,
    builder: (_) => MealEntryNutrientsSheet(entry: entry, onChanged: onChanged),
  );
}

class MealEntryNutrientsSheet extends StatefulWidget {
  const MealEntryNutrientsSheet({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  final MealEntry entry;
  final ValueChanged<MealEntry> onChanged;

  @override
  State<MealEntryNutrientsSheet> createState() =>
      _MealEntryNutrientsSheetState();
}

class _MealEntryNutrientsSheetState extends State<MealEntryNutrientsSheet> {
  late MealEntry _entry = widget.entry;

  void _change(MealEntry changed) {
    setState(() => _entry = changed);
    widget.onChanged(changed);
  }

  @override
  Widget build(BuildContext context) {
    return InkSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_entry.name, style: InkText.section),
          const SizedBox(height: 12),
          _row('nutrition.food.carbs', 'g', _entry.carbs, 999, (value) {
            _change(_entry.withNutrients(carbs: value));
          }),
          _row('nutrition.food.protein', 'g', _entry.protein, 999, (value) {
            _change(_entry.withNutrients(protein: value));
          }),
          _row('nutrition.food.fat', 'g', _entry.fat ?? 0, 999, (value) {
            _change(_entry.withNutrients(fat: value));
          }),
          _row('nutrition.food.energy', 'kcal', _entry.kcal ?? 0, 9999, (
            value,
          ) {
            _change(_entry.withNutrients(kcal: value));
          }),
        ],
      ),
    );
  }

  /// The nutrient's name on the left, its value editable in place on the right.
  Widget _row(
    String labelKey,
    String unit,
    double value,
    double max,
    ValueChanged<double> onSubmit,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: LocaleText(labelKey, style: InkText.row)),
          SportEditableNumber(
            key: ValueKey('$labelKey-$value'),
            valueText: '${sportDecimal(value, 0)} $unit',
            initial: value,
            min: 0,
            max: max,
            width: 110,
            onSubmit: onSubmit,
          ),
        ],
      ),
    );
  }
}
