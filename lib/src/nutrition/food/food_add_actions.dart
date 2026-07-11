import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/food/barcode_scan_page.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_search_page.dart';
import 'package:insulink/src/nutrition/food/off_client.dart';

/// Scans a barcode, looks it up in the product database, and opens the editor
/// pre-filled so the user can complete/adjust before saving. An unknown barcode
/// opens a blank editor carrying the code.
Future<void> scanAndEditProduct(BuildContext context) async {
  final barcode = await scanBarcode(context);
  if (barcode == null || !context.mounted) {
    return;
  }
  FoodProduct? found;
  try {
    found = await const OffClient().lookup(barcode);
  } catch (_) {
    found = null;
  }
  if (!context.mounted) {
    return;
  }
  await showFoodEditor(
    context,
    product: found ?? FoodProduct.blank(barcode: barcode),
  );
}

/// Opens the product-database search page.
void openFoodSearch(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const FoodSearchPage()));
}

/// The three ways to add a product — manual, database search, barcode scan —
/// shared by the nutrition page header and the bolus product picker so both
/// offer the same options. Each action saves into the product list, so a picker
/// watching that list sees the new entry immediately.
class FoodAddActions extends StatelessWidget {
  const FoodAddActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 24),
          onPressed: () => showFoodEditor(context),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.search, size: 24),
          onPressed: () => openFoodSearch(context),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.qr_code_scanner, size: 22),
          onPressed: () => scanAndEditProduct(context),
        ),
      ],
    );
  }
}
