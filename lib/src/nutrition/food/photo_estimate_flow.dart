import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/alert/loader_alert.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/photo_estimate.dart';

/// Takes a meal photo, has the server estimate it and opens the editor on the
/// result.
///
/// The estimate is a guess about a plate, not a label, so it is treated like an
/// Open Food Facts entry and stricter: it goes through the editor with a notice
/// to check it, and the portion and the confirmation still follow before any
/// dose. The camera hands back a JPEG already scaled to 1024 px and compressed;
/// that is what the server estimates and keeps.
///
/// Returns the product the editor saved. Null when the photo was cancelled, the
/// estimate failed or saw no food (both said in a dialog), or the editor was
/// dismissed.
Future<FoodProduct?> photographAndEditProduct(BuildContext context) async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 70,
  );
  if (photo == null || !context.mounted) {
    return null;
  }
  final estimate = await _estimateWithLoader(context, photo);
  if (!context.mounted) {
    return null;
  }
  if (estimate == null || !estimate.hasFood) {
    _sayNoEstimate(context, estimate);
    return null;
  }
  return showFoodEditor(
    context,
    product: estimate.product(
      Locales.string(context, 'nutrition.food.photo.serving'),
    ),
    noticeKey: 'nutrition.food.photo.check',
  );
}

/// The estimate behind the spinner card, which goes away either way.
Future<PhotoEstimate?> _estimateWithLoader(
  BuildContext context,
  XFile photo,
) async {
  const LoaderAlert().show(context);
  final jpeg = await photo.readAsBytes();
  final estimate = context.mounted
      ? await PhotoEstimate.request(context, jpeg)
      : null;
  if (context.mounted) {
    Navigator.pop(context);
  }
  return estimate;
}

/// Failed outright, or answered but found nothing to eat on the photo.
void _sayNoEstimate(BuildContext context, PhotoEstimate? estimate) {
  Alert(
    type: AlertType.error,
    description: estimate == null
        ? 'nutrition.food.photo.failed'
        : 'nutrition.food.photo.no_food',
  ).show(context);
}
