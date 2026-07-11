import 'package:flutter/cupertino.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/nutrition/food/food_section.dart';
import 'package:insulink/src/nutrition/hydration/hydration_card.dart';
import 'package:insulink/src/nutrition/meal/meal_section.dart';
import 'package:insulink/src/nutrition/stats/nutrition_stats_section.dart';

/// Nutrition tab. Hydration tracking up top; more sections land here later.
class NutritionBody extends AppPageBody {
  NutritionBody({super.key})
    : super(
        name: "nutrition.label",
        unselectedIcon: CupertinoIcons.cart,
        selectedIcon: CupertinoIcons.cart_fill,
      );

  @override
  Widget content(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      // Bottom padding keeps the centered injection FAB (page.dart) clear.
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
      children: const [
        NutritionStatsSection(),
        SizedBox(height: 28),
        HydrationCard(),
        SizedBox(height: 28),
        MealSection(),
        SizedBox(height: 28),
        FoodSection(),
      ],
    );
  }
}
