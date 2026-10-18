import 'package:flutter/material.dart';
import 'package:insulink/src/base/stepper_pill.dart';
import 'package:insulink/src/injection/meal_camera_page.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
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

/// Lists under the carbs field the foods the photo estimate saw, most
/// carbohydrates first and the small ones folded into "Sonstiges"
/// ([PhotoEstimate.summary]): "Banane · 120 g" on the left, its "25 g KH" on
/// the right, a muted camera icon in front of the first. An oversized portion
/// of one food shows here at a glance instead of hiding in the total.
///
/// A food the model counted in pieces carries a "− 4 +" counter between the
/// two: a miscounted plate is corrected through [onRecount] with one tap
/// instead of another photo. It never goes below one piece; a food that is not
/// there at all is typed over in the carbs field like any wrong estimate.
class PhotoCarbsNotice extends StatelessWidget {
  const PhotoCarbsNotice({
    super.key,
    required this.estimate,
    required this.onRecount,
  });

  final PhotoEstimate estimate;
  final void Function(PhotoEstimateItem item, int count) onRecount;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final style = InkText.label.copyWith(color: colors.muted);
    final carbsUnit = Locales.string(context, 'nutrition.food.carbs');
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4),
      child: Row(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              PhosphorIconsRegular.camera,
              size: 16,
              color: colors.muted,
            ),
          ),
          Expanded(
            child: Column(
              spacing: 4,
              children: [
                for (final item in estimate.summary(
                  Locales.string(context, 'injection.photo.other'),
                ))
                  _itemRow(item, style, carbsUnit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(PhotoEstimateItem item, TextStyle style, String carbsUnit) {
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: Text(
            '${item.name} · ${sportDecimal(item.grams, 0)} g',
            style: style,
          ),
        ),
        if (item.countable) _counter(item),
        Text('${sportDecimal(item.carbs, 0)} g $carbsUnit', style: style),
      ],
    );
  }

  Widget _counter(PhotoEstimateItem item) {
    return StepperPill(
      value: '${item.count}',
      onMinus: item.count > 1 ? () => onRecount(item, item.count - 1) : null,
      onPlus: () => onRecount(item, item.count + 1),
      minusLabelKey: 'injection.photo.fewer',
      plusLabelKey: 'injection.photo.more',
    );
  }
}
