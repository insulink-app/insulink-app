import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product_card.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:provider/provider.dart';

/// Full list of all stored products, reached via "show more" on the nutrition
/// page (which shows only the 3 most recent). Same cards, same actions.
class FoodProductsPage extends StatelessWidget {
  const FoodProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FoodState>();
    final products = state.products;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('nutrition.food.all'),
      ),
      body: ListView.separated(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final product = products[index];
          return FoodProductCard(
            product: product,
            onTap: () => showFoodEditor(context, product: product),
            onRemove: () => confirmDelete(
              context,
              messageKey: 'nutrition.food.delete_confirm',
              onConfirm: () => state.removeProduct(product),
            ),
          );
        },
      ),
    );
  }
}
