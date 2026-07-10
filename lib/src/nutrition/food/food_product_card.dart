import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';

/// One stored product: a unit-aware icon badge, name/brand, and its per-100 g
/// macros as color-coded pills. Tap opens the portion picker; the × removes it.
class FoodProductCard extends StatelessWidget {
  const FoodProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onRemove,
  });

  final FoodProduct product;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  static const _carbsColor = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(scheme),
              const SizedBox(width: 12),
              Expanded(child: _details(scheme)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A round icon badge tinted with the primary color: a drink glass for `ml`
  /// products, cutlery for solids.
  Widget _badge(ColorScheme scheme) {
    final isDrink = product.unit == 'ml';
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isDrink ? Icons.local_drink_rounded : Icons.restaurant_rounded,
        color: scheme.primary,
        size: 22,
      ),
    );
  }

  Widget _details(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name.isEmpty ? product.barcode : product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        _subtitle(scheme),
      ],
    );
  }

  /// Brand and/or the reported serving, whichever exist.
  Widget _subtitle(ColorScheme scheme) {
    final parts = [
      if (product.brand.isNotEmpty) product.brand,
      if (product.servingLabel.isNotEmpty) product.servingLabel,
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _pill(String labelKey, double value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_format(value)}$unit',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          LocaleText(
            labelKey,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.9),
            ),
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
