import 'package:flutter/material.dart';
import 'package:insulink/src/injection/meal_camera_page.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The camera button in the top right corner of the bolus calculator's carbs
/// card. Opens [MealCameraPage] and reports the estimate taken there through
/// [onEstimate]; backing out reports nothing, so the field keeps whatever the
/// user had typed.
class PhotoCarbsButton extends StatelessWidget {
  const PhotoCarbsButton({super.key, required this.onEstimate});

  final void Function(PhotoEstimate estimate) onEstimate;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: Locales.string(context, 'injection.photo.take'),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(PhosphorIconsBold.camera, size: 22),
      onPressed: () => _photograph(context),
    );
  }

  Future<void> _photograph(BuildContext context) async {
    final estimate = await photographMeal(context);
    if (estimate != null) {
      onEstimate(estimate);
    }
  }
}
