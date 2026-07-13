import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_detail_sheet.dart';
import 'package:insulink/src/sport/sport_leading_badge.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One logged meal as a list tile, matching the sport activity tiles: a tinted
/// badge, the carb amount as the title (a meal is characterized by its carbs),
/// the bolus + product count as subtitle, and the date/time trailing. Tap opens
/// [MealDetailSheet].
class MealCard extends StatelessWidget {
  const MealCard({super.key, required this.meal, this.showDate = true});

  final Meal meal;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    return ListTile(
      tileColor: scheme.onSurface.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      leading: const SportLeadingBadge(icon: PhosphorIconsRegular.forkKnife),
      title: Text(
        '${meal.carbs.toStringAsFixed(0)} g '
        '${Locales.string(context, 'nutrition.stats.carbs')}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(_subtitle(context)),
      trailing: _trailing(context, locale),
      onTap: () => showMealDetail(context, meal),
    );
  }

  String _subtitle(BuildContext context) {
    final bolus = '${meal.bolus.toStringAsFixed(1)} E';
    if (meal.entries.isEmpty) {
      return bolus;
    }
    final products = Locales.string(
      context,
      'nutrition.meals.products_count',
      params: ['${meal.entries.length}'],
    );
    return '$bolus · $products';
  }

  /// Right-hand corner: the time, with the date stacked above it (the home list
  /// and the log page have no day section headers).
  Widget _trailing(BuildContext context, MaterialLocalizations locale) {
    final scheme = Theme.of(context).colorScheme;
    final time = Text(
      locale.formatTimeOfDay(TimeOfDay.fromDateTime(meal.time)),
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface.withValues(alpha: 0.7),
      ),
    );
    if (!showDate) {
      return time;
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          locale.formatMediumDate(meal.time),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        time,
      ],
    );
  }
}
