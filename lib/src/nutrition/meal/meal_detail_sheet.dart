import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/meal/meal_time.dart';
import 'package:provider/provider.dart';

/// Opens the details of a logged [meal]: carbs / glucose / bolus, and — when the
/// bolus was dosed over the food database — the products that made it up.
Future<void> showMealDetail(BuildContext context, Meal meal) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MealDetailSheet(meal: meal),
  );
}

class MealDetailSheet extends StatelessWidget {
  const MealDetailSheet({super.key, required this.meal});

  final Meal meal;

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
        Text.rich(
          TextSpan(
            text: meal.carbs.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
            children: [
              TextSpan(
                text: ' g ${Locales.string(context, 'nutrition.food.carbs')}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Text(
          mealTimeLabel(meal.time),
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      ],
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
          _statRow(context, Icons.bloodtype_rounded, 'injection.glucose',
              '${meal.glucoseMgdl} mg/dL'),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          _statRow(context, Icons.water_drop_rounded, 'injection.bolus',
              '${meal.bolus.toStringAsFixed(1)} E'),
        ],
      ),
    );
  }

  Widget _statRow(
    BuildContext context,
    IconData icon,
    String labelKey,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: LocaleText(
              labelKey,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(BuildContext context, MealEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
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
                    '${_amount(entry.amount)} ${entry.unit}',
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
          ],
        ),
      ),
    );
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
      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
      label: LocaleText(
        'nutrition.meals.delete',
        style: const TextStyle(color: Colors.redAccent),
      ),
    );
  }

  String _amount(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
