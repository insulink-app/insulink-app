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
///
/// [onKnown] changes what an ALREADY SAVED product means. On the nutrition page
/// a scan is how you find a product to edit, so the editor is right. In the bolus
/// picker the same scan is how you CHOOSE one, and stopping at the editor puts a
/// form in front of somebody who has already said which product they mean; the
/// picker passes a callback that carries it straight on to the amount instead.
///
/// Only the saved case is diverted. A product found on Open Food Facts is not
/// yet the user's, and its carbohydrate figure is routinely wrong, so it still
/// goes through the editor to be looked at before a dose is computed from it.
Future<void> scanAndEditProduct(
  BuildContext context, {
  void Function(FoodProduct product)? onKnown,
}) async {
  final barcode = await scanBarcode(context);
  if (barcode == null || !context.mounted) {
    return;
  }
  final known = context.read<FoodState>().findByBarcode(barcode);
  if (known != null) {
    if (onKnown != null) {
      onKnown(known);
      return;
    }
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
  const FoodAddActions({super.key, this.onScanRequested});

  /// Takes the scan over entirely, instead of this widget running it.
  ///
  /// The bolus picker passes one because the scanner is a full-screen page
  /// pushed ON TOP of the picker sheet: scanning from inside it means the sheet
  /// is revealed again the moment the scanner pops, then closes on its way to
  /// the amount, which looks like a stray popup opening and shutting. The picker
  /// closes itself first and scans afterwards.
  final VoidCallback? onScanRequested;

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
          onPressed: onScanRequested ?? () => scanAndEditProduct(context),
        ),
      ],
    );
  }
}
