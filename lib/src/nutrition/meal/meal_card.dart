import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_detail_sheet.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One logged meal as a list tile, matching the sport activity tiles: a tinted
/// badge, the carb amount as the title (a meal is characterized by its carbs),
/// the bolus + product count as subtitle, and the date/time trailing. Tap opens
/// [MealDetailSheet].
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.meal,
    this.showDate = true,
    this.framed = true,
  });

  final Meal meal;
  final bool showDate;

  /// A row standing on its own gets its own panel; inside an
  /// [InkPanel.list] it is a bare row and the panel draws the lines.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final row = ListRow(
      icon: PhosphorIconsBold.forkKnife,
      title:
          '${sportDecimal(meal.carbs, 0)} g '
          '${Locales.string(context, 'nutrition.stats.carbs')}',
      subtitle: _subtitle(context),
      trailing: _trailing(context),
      onTap: () => showMealDetail(context, meal),
    );
    return framed ? InkPanel.list(rows: [row]) : row;
  }

  String _subtitle(BuildContext context) {
    final bolus = Locales.string(
      context,
      'nutrition.meals.bolus_value',
      params: [sportDecimal(meal.bolus, 1)],
    );
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

  /// Right-hand corner: the time, with the day named above it (the home list
  /// has no day section headers; the log page does, and shows the time only).
  Widget _trailing(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(meal.time),
      alwaysUse24HourFormat: true,
    );
    if (!showDate) {
      return Text(time, style: InkText.row);
    }
    return ListRowMeta(date: RelativeDay(meal.time).label(context), time: time);
  }
}
