import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/food/barcode_scan_page.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_product_card.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/food/off_client.dart';
import 'package:provider/provider.dart';

/// Product database section: the products the user scanned, each with its
/// per-100 g nutrition, plus a scan button to add more (Open Food Facts lookup).
class FoodSection extends StatefulWidget {
  const FoodSection({super.key});

  @override
  State<FoodSection> createState() => _FoodSectionState();
}

class _FoodSectionState extends State<FoodSection> {
  bool _loading = false;

  /// Scan a barcode, look it up in Open Food Facts, and open the editor
  /// pre-filled — so the user can complete missing fields (or fill everything in
  /// when the barcode is unknown) before saving.
  Future<void> _scan() async {
    final barcode = await scanBarcode(context);
    if (barcode == null || !mounted) {
      return;
    }
    setState(() => _loading = true);
    final product = await _lookup(barcode);
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    await showFoodEditor(
      context,
      product: product ?? FoodProduct.blank(barcode: barcode),
    );
  }

  Future<FoodProduct?> _lookup(String barcode) async {
    try {
      return await const OffClient().lookup(barcode);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<FoodState>().products;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 12),
        if (products.isEmpty) _empty() else _list(products),
      ],
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'nutrition.food',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        _loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 24),
                    onPressed: () => showFoodEditor(context),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.qr_code_scanner, size: 22),
                    onPressed: _scan,
                  ),
                ],
              ),
      ],
    );
  }

  Widget _list(List<FoodProduct> products) {
    final state = context.read<FoodState>();
    return Column(
      children: [
        for (final product in products)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FoodProductCard(
              product: product,
              onTap: () => showFoodEditor(context, product: product),
              onRemove: () => state.removeProduct(product),
            ),
          ),
      ],
    );
  }

  Widget _empty() {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _loading ? null : _scan,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Icon(Icons.qr_code_scanner, size: 32, color: Colors.grey[500]),
            const SizedBox(height: 10),
            LocaleText(
              'nutrition.food.empty',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
