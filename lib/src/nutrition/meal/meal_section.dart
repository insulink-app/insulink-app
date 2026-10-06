import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/meal/meal_card.dart';
import 'package:insulink/src/nutrition/meal/meal_log_page.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/section_header.dart';

/// The meal log on the nutrition page: the three most recent meals as tiles
/// (matching the sport activity list), with a "Show more" into the full log
/// page. Tapping a meal opens its detail sheet.
class MealSection extends StatelessWidget {
  const MealSection({super.key});

  static const _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    final recent = meals.take(_maxVisible).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(titleKey: 'nutrition.meals', topGap: 0),
        if (recent.isEmpty)
          _empty(context)
        else
          InkPanel.list(
            rows: [
              for (final meal in recent) MealCard(meal: meal, framed: false),
            ],
          ),
        if (meals.length > recent.length) _showMore(context),
      ],
    );
  }

  Widget _showMore(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const MealLogPage())),
        child: LocaleText('nutrition.meals.show_more'),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return const EmptyState(
      icon: PhosphorIconsBold.forkKnife,
      titleKey: 'nutrition.meals.empty',
      subtitleKey: 'nutrition.meals.empty_hint',
    );
  }
}
