import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_add_actions.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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
  return showInkSheet<_PickerOutcome>(
    context: context,
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
    final products = context.watch<FoodState>().products;
    final filtered = _filtered(products);
    return InkSheet(
      title: Row(
        children: [
          Expanded(
            child: LocaleText(
              'injection.products.pick',
              style: InkText.bigValue.copyWith(fontSize: 20),
            ),
          ),
          FoodAddActions(
            onScanRequested: () =>
                Navigator.of(context).pop(const _PickerOutcome.scan()),
            onCreated: (product) =>
                Navigator.of(context).pop(_PickerOutcome.picked(product)),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  PhosphorIconsBold.magnifyingGlass,
                  color: context.ink.muted,
                ),
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
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                children: [
                  _columnHeads(),
                  const SizedBox(height: 8),
                  InkPanel.list(
                    color: context.ink.panelRaised,
                    rows: [for (final product in filtered) _tile(product)],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// "Saved products" on the left, what the number on the right means on the
  /// right.
  Widget _columnHeads() {
    final style = InkText.caption.copyWith(color: context.ink.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(child: LocaleText('injection.products.saved', style: style)),
          LocaleText('injection.products.carbs_column', style: style),
        ],
      ),
    );
  }

  /// One product: name over brand, its carbs per 100 g on the right. The whole
  /// row picks it; no icon and no chevron.
  Widget _tile(FoodProduct product) {
    final colors = context.ink;
    return InkWell(
      onTap: () => Navigator.of(context).pop(_PickerOutcome.picked(product)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      product.name.isEmpty ? product.barcode : product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InkText.row.copyWith(color: colors.text),
                    ),
                    if (product.brand.isNotEmpty)
                      Text(
                        product.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: InkText.caption.copyWith(color: colors.muted),
                      ),
                  ],
                ),
              ),
              Text(
                '${sportDecimal(product.carbs100g, 0)} g',
                style: InkText.rowTitle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
