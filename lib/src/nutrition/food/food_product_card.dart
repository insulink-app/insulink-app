import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One stored product: a unit-aware icon badge with its name, brand and reported
/// serving. Tap opens the portion picker; the × removes it.
class FoodProductCard extends StatelessWidget {
  const FoodProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onRemove,
    this.framed = true,
  });

  final FoodProduct product;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// A row standing on its own gets its own panel; inside an
  /// [InkPanel.list] it is a bare row and the panel draws the lines.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final row = ListRow(
      icon: product.unit == 'ml'
          ? PhosphorIconsBold.drop
          : PhosphorIconsBold.forkKnife,
      tone: ListRowTone.neutral,
      title: product.name.isEmpty ? product.barcode : product.name,
      subtitle: _subtitle(),
      trailing: IconButton(
        tooltip: Locales.string(context, 'nutrition.food.remove'),
        icon: Icon(PhosphorIconsBold.x, size: 18, color: context.ink.muted),
        onPressed: onRemove,
      ),
      onTap: onTap,
    );
    return framed ? InkPanel.list(rows: [row]) : row;
  }

  /// Brand and/or the reported serving, whichever exist.
  String? _subtitle() {
    final parts = [
      if (product.brand.isNotEmpty) product.brand,
      if (product.servingLabel.isNotEmpty) product.servingLabel,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
}
