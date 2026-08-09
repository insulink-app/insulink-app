import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/food/barcode_scan_page.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_search_page.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/food/off_client.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Scans a barcode and opens the editor on the matching product.
///
/// The user's OWN saved product wins: a barcode already in [FoodState] opens
/// that entry, with no Open Food Facts lookup at all. Re-scanning used to go
/// straight to OFF and hand the editor the remote values, so every re-scan threw
/// away the corrections the user had made to that product (OFF's carbs are
/// routinely off, and a manually created product isn't in OFF at all — it came
/// back blank). Only an unknown barcode is looked up remotely, and an unknown
/// one that OFF doesn't have either opens a blank editor carrying the code.
Future<void> scanAndEditProduct(BuildContext context) async {
  final barcode = await scanBarcode(context);
  if (barcode == null || !context.mounted) {
    return;
  }
  final known = context.read<FoodState>().findByBarcode(barcode);
  if (known != null) {
    await showFoodEditor(context, product: known);
    return;
  }
  final found = await _lookUp(barcode);
  if (!context.mounted) {
    return;
  }
  await showFoodEditor(
    context,
    product: found ?? FoodProduct.blank(barcode: barcode),
  );
}

/// The Open Food Facts entry for [barcode], or null when it has none or the
/// lookup failed — an offline scan must still open the editor.
Future<FoodProduct?> _lookUp(String barcode) async {
  try {
    return await const OffClient().lookup(barcode);
  } catch (_) {
    return null;
  }
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
          icon: const Icon(PhosphorIconsBold.plus, size: 24),
          onPressed: () => showFoodEditor(context),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 24),
          onPressed: () => openFoodSearch(context),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(PhosphorIconsBold.qrCode, size: 22),
          onPressed: () => scanAndEditProduct(context),
        ),
      ],
    );
  }
}
