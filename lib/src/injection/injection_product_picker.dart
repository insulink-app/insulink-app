import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_add_actions.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Searchable bottom-sheet list to pick one saved product. Also offers the same
/// add / search / scan actions as the nutrition page ([FoodAddActions]), so a
/// product can be created on the spot and then picked. Returns the chosen
/// [FoodProduct] (or null when dismissed).
///
/// **The scan runs between two showings of the sheet, never on top of one.** The
/// scanner is a full-screen page, so scanning from inside the sheet reveals the
/// sheet again the instant the scanner pops and then closes it on the way to the
/// amount, which reads as a stray popup opening and shutting. Here the sheet
/// closes first. A scan that settles on a product goes straight on, whether it
/// was already saved or created in the editor there and then; a cancelled one
/// brings the picker back so the user can carry on where they were.
Future<FoodProduct?> pickFoodProduct(BuildContext context) async {
  while (true) {
    if (!context.mounted) {
      return null;
    }
    final outcome = await _showPicker(context);
    if (outcome == null || outcome.product != null) {
      return outcome?.product;
    }
    if (!context.mounted) {
      return null;
    }
    final scanned = await _scanForPick(context);
    if (scanned != null) {
      return scanned;
    }
  }
}

Future<_PickerOutcome?> _showPicker(BuildContext context) {
  return showModalBottomSheet<_PickerOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ProductPicker(),
  );
}

/// Scans and reports back the product it settled on.
///
/// A saved product is taken as chosen (`editKnown: false`) — the user has just
/// pointed the camera at it. An unknown barcode still goes through the editor: a
/// product from Open Food Facts is not yet the user's, and its carbohydrate
/// figure is routinely wrong, so it is looked at before a dose is computed from
/// it, and what it saves is then the choice.
Future<FoodProduct?> _scanForPick(BuildContext context) =>
    scanAndEditProduct(context, editKnown: false);

/// What the picker sheet came back with: a product, or a request to scan.
class _PickerOutcome {
  const _PickerOutcome.picked(this.product);

  const _PickerOutcome.scan() : product = null;

  final FoodProduct? product;
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker();

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FoodProduct> _filtered(List<FoodProduct> products) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return products;
    }
    return [
      for (final product in products)
        if ('${product.name} ${product.brand}'.toLowerCase().contains(query))
          product,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final products = context.watch<FoodState>().products;
    final filtered = _filtered(products);
    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsBold.arrowLeft),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: LocaleText(
                    'injection.products.pick',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FoodAddActions(
                  onScanRequested: () => Navigator.of(context)
                      .pop(const _PickerOutcome.scan()),
                  onCreated: (product) => Navigator.of(context)
                      .pop(_PickerOutcome.picked(product)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                hintText: Locales.string(context, 'injection.products.search'),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(PhosphorIconsBold.x),
                        onPressed: _search.clear,
                      ),
              ),
            ),
          ),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: LocaleText(
                'nutrition.food.empty',
                textAlign: TextAlign.center,
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: LocaleText(
                'injection.products.none',
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: filtered.length,
                itemBuilder: (context, index) => _tile(filtered[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(FoodProduct product) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (product.brand.isNotEmpty) product.brand,
      Locales.string(
        context,
        'injection.products.carbs_per_100',
        params: [product.carbs100g.toStringAsFixed(0)],
      ),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () =>
              Navigator.of(context).pop(_PickerOutcome.picked(product)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                _badge(scheme, product.unit == 'ml'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name.isEmpty ? product.barcode : product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  PhosphorIconsBold.caretRight,
                  color: scheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(ColorScheme scheme, bool isDrink) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isDrink ? PhosphorIconsBold.drop : PhosphorIconsBold.forkKnife,
        color: scheme.onSurfaceVariant,
        size: 20,
      ),
    );
  }
}
