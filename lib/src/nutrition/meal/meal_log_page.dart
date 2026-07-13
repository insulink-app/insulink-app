import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_card.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Full meal log: every logged meal as a tile, newest first, grouped by day.
/// Reached from the "Show more" button in [MealSection].
class MealLogPage extends StatelessWidget {
  const MealLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('nutrition.meals'),
      ),
      body: meals.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsRegular.forkKnife,
              titleKey: 'nutrition.meals.empty',
              subtitleKey: 'nutrition.meals.empty_hint',
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                for (var index = 0; index < meals.length; index++) ...[
                  if (_startsNewDay(meals, index))
                    _dayHeader(context, meals[index].time, index == 0),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MealCard(meal: meals[index], showDate: false),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _dayHeader(BuildContext context, DateTime day, bool first) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 8),
      child: Text(
        MaterialLocalizations.of(context).formatFullDate(day),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  /// True when [index] falls on a different calendar day than the meal before it.
  bool _startsNewDay(List<Meal> meals, int index) {
    if (index == 0) {
      return true;
    }
    return !_sameDay(meals[index].time, meals[index - 1].time);
  }

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
