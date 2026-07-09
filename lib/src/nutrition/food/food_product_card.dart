import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';

/// One stored product: name/brand and its per-100 g macros, with a remove
/// button.
class FoodProductCard extends StatelessWidget {
  const FoodProductCard({
    super.key,
    required this.product,
    required this.onRemove,
  });

  final FoodProduct product;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _details(theme)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _details(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name.isEmpty ? product.barcode : product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        if (product.brand.isNotEmpty)
          Text(
            product.brand,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        const SizedBox(height: 10),
        _macros(theme),
      ],
    );
  }

  Widget _macros(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    return Row(
      children: [
        _macro('nutrition.food.carbs', product.carbs100g, 'g', accent),
        _macro('nutrition.food.fat', product.fat100g, 'g', accent),
        _macro('nutrition.food.protein', product.protein100g, 'g', accent),
        _macro('nutrition.food.kcal', product.kcal100g, '', accent),
      ],
    );
  }

  Widget _macro(String labelKey, double value, String unit, Color accent) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_format(value)}$unit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          LocaleText(
            labelKey,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// Grams/kcal with at most one decimal, trailing zero trimmed (12.0 → "12").
  String _format(double value) {
    var text = value.toStringAsFixed(1);
    if (text.endsWith('.0')) {
      text = text.substring(0, text.length - 2);
    }
    return text.replaceAll('.', ',');
  }
}
