import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/meal/meal_time.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Opens the details of a logged [meal]: carbs / glucose / bolus, and — when the
/// bolus was dosed over the food database — the products that made it up.
Future<void> showMealDetail(BuildContext context, Meal meal) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          _header(context),
          const SizedBox(height: 20),
          _stats(context),
          if (meal.entries.isNotEmpty) ...[
            const SizedBox(height: 24),
            LocaleText(
              'nutrition.meals.products',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            for (final entry in meal.entries) _entryRow(context, entry),
          ],
          const SizedBox(height: 24),
          _deleteButton(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _carbs(context)),
        _timeButton(context),
      ],
    );
  }

  /// The carbs headline. Editable inline for a manual meal; read-only when the
  /// meal was dosed over the food database, where the total is the sum of the
  /// listed products (edit those, not the total).
  Widget _carbs(BuildContext context) {
    const numberStyle = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.bold,
      height: 1,
    );
    const suffixStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    final suffix = ' g ${Locales.string(context, 'nutrition.food.carbs')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (meal.entries.isEmpty)
          SportEditableNumber(
            valueText: meal.carbs.toStringAsFixed(0),
            initial: meal.carbs,
            min: 0,
            max: 999,
            width: 74,
            style: numberStyle,
            onSubmit: (value) => _update(meal.copyWith(carbs: value)),
          )
        else
          Text(meal.carbs.toStringAsFixed(0), style: numberStyle),
        Flexible(
          child: Text(
            suffix,
            style: suffixStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// The meal time, tappable to correct it via the native date/time pickers.
  Widget _timeButton(BuildContext context) {
    return TextButton(
      onPressed: _editTime,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        mealTimeLabel(meal.time),
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _stats(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          _statRow(
            context,
            PhosphorIconsBold.drop,
            'injection.glucose',
            SportEditableNumber(
              valueText: '${meal.glucoseMgdl} mg/dL',
              initial: meal.glucoseMgdl.toDouble(),
              min: 20,
              max: 600,
              width: 104,
              onSubmit: (value) =>
                  _update(meal.copyWith(glucoseMgdl: value.round())),
            ),
          ),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          _statRow(
            context,
            PhosphorIconsBold.drop,
            'injection.bolus',
            SportEditableNumber(
              valueText: '${meal.bolus.toStringAsFixed(1)} E',
              initial: meal.bolus,
              min: 0,
              max: 100,
              decimal: true,
              width: 88,
              onSubmit: (value) => _update(meal.copyWith(bolus: value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(
    BuildContext context,
    IconData icon,
    String labelKey,
    Widget trailing,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: LocaleText(
              labelKey,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _entryRow(BuildContext context, MealEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final product = _findProduct(context, entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: product == null
              ? null
              : () => showFoodEditor(context, product: product),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _entrySubtitle(context, entry),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${entry.carbs.toStringAsFixed(0)} g',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (product != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      PhosphorIconsBold.caretRight,
                      color: scheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
      icon: Icon(PhosphorIconsBold.trash, size: 20, color: context.danger),
      label: LocaleText(
        'nutrition.meals.delete',
        style: TextStyle(color: context.danger),
      ),
    );
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
