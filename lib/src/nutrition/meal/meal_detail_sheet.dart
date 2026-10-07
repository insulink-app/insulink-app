import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Opens the details of a logged [meal]: carbs / glucose / bolus, and — when the
/// bolus was dosed over the food database — the products that made it up.
Future<void> showMealDetail(BuildContext context, Meal meal) {
  return showInkSheet(
    context: context,
    builder: (_) => MealDetailSheet(meal: meal),
  );
}

class MealDetailSheet extends StatefulWidget {
  const MealDetailSheet({super.key, required this.meal});

  final Meal meal;

  @override
  State<MealDetailSheet> createState() => _MealDetailSheetState();
}

class _MealDetailSheetState extends State<MealDetailSheet> {
  /// The live meal shown, replaced in place on every inline edit so the sheet
  /// reflects the change without reopening.
  late Meal meal = widget.meal;

  /// Persists an edit through [MealState] (matched by identity) and adopts the
  /// new instance so subsequent edits build on it.
  void _update(Meal updated) {
    context.read<MealState>().updateMeal(meal, updated);
    setState(() => meal = updated);
  }

  /// Opens the native date + time pickers to correct when the meal was logged.
  Future<void> _editTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: meal.time,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(meal.time),
    );
    if (time == null) {
      return;
    }
    _update(
      meal.copyWith(
        time: DateTime(date.year, date.month, date.day, time.hour, time.minute),
      ),
    );
  }

  /// Header with the meal's time, the carbs / glucose / bolus strip, the
  /// products, and "Mahlzeit löschen" at the foot
  /// (`docs/redesign/screens/39-mahlzeit-detail.png`).
  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return InkSheet(
      title: _header(colors),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stats(colors),
            if (meal.entries.isNotEmpty) ...[
              _productsHeader(colors),
              _products(colors),
            ],
            const SizedBox(height: 16),
            Center(child: _deleteButton(context)),
          ],
        ),
      ),
    );
  }

  /// Cutlery in an accent disc, "Mahlzeit", and the time under it, tappable
  /// to correct it.
  Widget _header(InsulinkColors colors) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(meal.time),
      alwaysUse24HourFormat: true,
    );
    return Row(
      spacing: 14,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withValues(alpha: 0.14),
          ),
          child: Icon(
            PhosphorIconsBold.forkKnife,
            size: 20,
            color: colors.accent,
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: _editTime,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                LocaleText(
                  'nutrition.meals.title',
                  style: InkText.bigValue.copyWith(fontSize: 20),
                ),
                Text(
                  '${RelativeDay(meal.time).label(context)}, $time',
                  style: InkText.label.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Carbs, glucose and bolus side by side on the page colour, parted by
  /// lines; each value editable in place as before. The carbs are read-only
  /// when they are the sum of the listed products.
  Widget _stats(InsulinkColors colors) {
    final bolusUnit = Locales.string(
      context,
      'injection.bolus.value',
      params: [''],
    ).trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(InkRadius.panel),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _stat(
                colors,
                PhosphorIconsBold.forkKnife,
                'nutrition.food.carbs',
                meal.entries.isEmpty
                    ? _editable(
                        sportDecimal(meal.carbs, 0),
                        meal.carbs,
                        0,
                        999,
                        (value) => _update(meal.copyWith(carbs: value)),
                        color: colors.accentText,
                      )
                    : Text(
                        sportDecimal(meal.carbs, 0),
                        style: _valueStyle.copyWith(color: colors.accentText),
                      ),
                'g',
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: colors.line),
            Expanded(
              child: _stat(
                colors,
                PhosphorIconsBold.drop,
                'nutrition.meals.glucose',
                _editable(
                  '${meal.glucoseMgdl}',
                  meal.glucoseMgdl.toDouble(),
                  20,
                  600,
                  (value) => _update(meal.copyWith(glucoseMgdl: value.round())),
                ),
                'mg/dL',
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: colors.line),
            Expanded(
              child: _stat(
                colors,
                PhosphorIconsBold.syringe,
                'injection.bolus',
                _editable(
                  sportDecimal(meal.bolus, 1),
                  meal.bolus,
                  0,
                  100,
                  (value) => _update(meal.copyWith(bolus: value)),
                  decimal: true,
                ),
                bolusUnit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _valueStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.1,
  );

  Widget _editable(
    String text,
    double initial,
    double min,
    double max,
    ValueChanged<double> onSubmit, {
    bool decimal = false,
    Color? color,
  }) {
    return SportEditableNumber(
      valueText: text,
      initial: initial,
      min: min,
      max: max,
      decimal: decimal,
      width: 15.0 * text.length + 6,
      plain: true,
      style: _valueStyle.copyWith(color: color),
      onSubmit: onSubmit,
    );
  }

  /// One figure of the strip: a small glyph and label, the value with its
  /// unit beside it.
  Widget _stat(
    InsulinkColors colors,
    IconData icon,
    String labelKey,
    Widget value,
    String unit,
  ) {
    return Column(
      spacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(icon, size: 16, color: colors.muted),
            LocaleText(
              labelKey,
              style: InkText.caption.copyWith(color: colors.muted),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 4,
            children: [
              value,
              Text(unit, style: InkText.unit.copyWith(color: colors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  /// "Produkte" with the count on the right.
  Widget _productsHeader(InsulinkColors colors) {
    final count = meal.entries.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: LocaleText(
              'nutrition.meals.products',
              style: InkText.section,
            ),
          ),
          LocaleText(
            count == 1
                ? 'nutrition.meals.products_count_one'
                : 'nutrition.meals.products_count',
            params: ['$count'],
            style: InkText.label.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }

  /// The products as rows on the page colour, parted by lines.
  Widget _products(InsulinkColors colors) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(InkRadius.panel),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var index = 0; index < meal.entries.length; index++) ...[
              if (index > 0)
                Divider(height: 1, thickness: 1, color: colors.line),
              _entryRow(colors, meal.entries[index]),
            ],
          ],
        ),
      ),
    );
  }

  /// Name over brand and portion, "33 g KH" on the right; a saved product
  /// opens its editor.
  Widget _entryRow(InsulinkColors colors, MealEntry entry) {
    final product = _findProduct(context, entry);
    final brand = product?.brand ?? '';
    final subtitle = _entrySubtitle(context, entry);
    final carbsUnit = Locales.string(context, 'nutrition.food.carbs');
    return InkWell(
      onTap: product == null
          ? null
          : () => showFoodEditor(context, product: product),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: InkText.rowTitle,
                  ),
                  Text(
                    brand.isEmpty ? subtitle : '$brand, $subtitle',
                    style: InkText.label.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                text: sportDecimal(entry.carbs, 0),
                style: InkText.rowTitle.copyWith(fontSize: 17),
                children: [
                  TextSpan(
                    text: ' g $carbsUnit',
                    style: InkText.label.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            if (product != null)
              Icon(PhosphorIconsBold.caretRight, size: 18, color: colors.muted),
          ],
        ),
      ),
    );
  }

  /// "Mahlzeit löschen" as a red text button, no fill; asks first.
  Widget _deleteButton(BuildContext context) {
    return TextButton.icon(
      onPressed: () => confirmDelete(
        context,
        messageKey: 'nutrition.meals.delete_confirm',
        onConfirm: () {
          context.read<MealState>().removeMeal(meal);
          Navigator.of(context).pop();
        },
      ),
      style: TextButton.styleFrom(foregroundColor: context.danger),
      icon: const Icon(PhosphorIconsBold.trash, size: 20),
      label: LocaleText(
        'nutrition.meals.delete',
        style: InkText.button.copyWith(color: context.danger),
      ),
    );
  }

  /// The still-saved product an [entry] came from (matched by barcode), or null
  /// when it was a manual entry or the product has since been deleted.
  FoodProduct? _findProduct(BuildContext context, MealEntry entry) {
    if (entry.barcode.isEmpty) {
      return null;
    }
    for (final product in context.read<FoodState>().products) {
      if (product.barcode == entry.barcode) {
        return product;
      }
    }
    return null;
  }

  /// The amount in the product's unit, prefixed with the serving count when the
  /// product declares a serving size (e.g. "2 Portionen · 60 g").
  String _entrySubtitle(BuildContext context, MealEntry entry) {
    final amount = '${_amount(entry.amount)} ${entry.unit}';
    final servings = entry.servings;
    if (servings == null) {
      return amount;
    }
    final label = servings == 1
        ? Locales.string(context, 'injection.products.serving_one')
        : Locales.string(context, 'injection.products.servings');
    return '${_amount(servings)} $label · $amount';
  }

  String _amount(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
