import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/food/barcode_scan_page.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_search_page.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/food/off_client.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/localization/locales.dart';

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
/// [editKnown] changes what an ALREADY SAVED product means. On the nutrition
/// page a scan is how you find a product to edit, so the editor is right. In the
/// bolus picker the same scan is how you CHOOSE one, and stopping at the editor
/// puts a form in front of somebody who has already said which product they
/// mean, so it passes false and the product is returned as it stands.
///
/// Only the saved case is diverted. A product found on Open Food Facts is not
/// yet the user's, and its carbohydrate figure is routinely wrong, so it still
/// goes through the editor to be looked at before a dose is computed from it.
///
/// Returns the product the scan settled on: the saved one, or the one the editor
/// saved. Null when nothing was scanned or the editor was dismissed. The picker
/// carries that straight on to the portion.
Future<FoodProduct?> scanAndEditProduct(
  BuildContext context, {
  bool editKnown = true,
}) async {
  final barcode = await scanBarcode(context);
  if (barcode == null || !context.mounted) {
    return null;
  }
  final known = context.read<FoodState>().findByBarcode(barcode);
  if (known != null) {
    return editKnown ? await showFoodEditor(context, product: known) : known;
  }
  final found = await _lookUp(barcode);
  if (!context.mounted) {
    return null;
  }
  return await showFoodEditor(
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

/// Opens the product-database search page, reporting back the product it saved.
Future<FoodProduct?> openFoodSearch(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<FoodProduct>(builder: (_) => const FoodSearchPage()),
  );
}

/// The three ways to add a product — manual, database search, barcode scan —
/// shared by the nutrition page header and the bolus product picker so both
/// offer the same options. Each action saves into the product list, so a picker
/// watching that list sees the new entry immediately.
class FoodAddActions extends StatelessWidget {
  const FoodAddActions({super.key, this.onScanRequested, this.onCreated});

  /// Takes the scan over entirely, instead of this widget running it.
  ///
  /// The bolus picker passes one because the scanner is a full-screen page
  /// pushed ON TOP of the picker sheet: scanning from inside it means the sheet
  /// is revealed again the moment the scanner pops, then closes on its way to
  /// the amount, which looks like a stray popup opening and shutting. The picker
  /// closes itself first and scans afterwards.
  final VoidCallback? onScanRequested;

  /// Reports a product the user just CREATED here (manually or off the database
  /// search), so a picker can take it straight to the portion.
  ///
  /// Without it a new product only landed in the list and the user had to go
  /// find it again, having just typed out every one of its fields. The nutrition
  /// page passes nothing, because there the list IS the destination.
  final void Function(FoodProduct product)? onCreated;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: Locales.string(context, 'nutrition.food.action.create'),
          icon: const Icon(PhosphorIconsBold.plus, size: 24),
          onPressed: () => _report(showFoodEditor(context)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: Locales.string(context, 'nutrition.food.action.search'),
          icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 24),
          onPressed: () => _report(openFoodSearch(context)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: Locales.string(context, 'nutrition.food.action.scan'),
          icon: const Icon(PhosphorIconsBold.qrCode, size: 22),
          onPressed: onScanRequested ?? () => scanAndEditProduct(context),
        ),
      ],
    );
  }

  /// Hands a freshly created product to [onCreated] once its sheet or page has
  /// closed. Dismissed without saving reports nothing.
  Future<void> _report(Future<FoodProduct?> creating) async {
    final created = await creating;
    if (created != null) {
      onCreated?.call(created);
    }
  }
}
