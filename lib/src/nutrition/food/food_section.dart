import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/food/food_add_actions.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_product_card.dart';
import 'package:insulink/src/nutrition/food/food_products_page.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/section_header.dart';

/// Product database section: the products the user added, each with its
/// per-100 g nutrition, plus add / search / scan actions (see [FoodAddActions]).
class FoodSection extends StatelessWidget {
  const FoodSection({super.key});

  @override
  Widget build(BuildContext context) {
    final products = context.watch<FoodState>().products;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        if (products.isEmpty) _empty(context) else _list(context, products),
      ],
    );
  }

  Widget _header() {
    return const SectionHeader(
      titleKey: 'nutrition.food',
      topGap: 0,
      actions: [FoodAddActions()],
    );
  }

  Widget _list(BuildContext context, List<FoodProduct> products) {
    final state = context.read<FoodState>();
    final visible = products.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkPanel.list(
          rows: [
            for (final product in visible)
              FoodProductCard(
                product: product,
                framed: false,
                onTap: () => showFoodEditor(context, product: product),
                onRemove: () => confirmDelete(
                  context,
                  messageKey: 'nutrition.food.delete_confirm',
                  onConfirm: () => state.removeProduct(product),
                ),
              ),
          ],
        ),
        if (products.length > 3) _showMore(context),
      ],
    );
  }

  Widget _showMore(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const FoodProductsPage())),
      child: LocaleText('nutrition.food.show_more'),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => scanAndEditProduct(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Icon(
              PhosphorIconsBold.qrCode,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            LocaleText(
              'nutrition.food.empty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
