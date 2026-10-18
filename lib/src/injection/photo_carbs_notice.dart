import 'package:flutter/material.dart';
import 'package:insulink/src/base/stepper_pill.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Lists under the carbs field the foods the photo estimate saw, most
/// carbohydrates first and the small ones folded into "Sonstiges"
/// ([PhotoEstimate.summary]), under a muted "Auf dem Foto: 72 g KH". That sum
/// stays visible after the user typed over the field, so the gap between the
/// photo and the typed value shows.
///
/// Each food takes two lines, its name over "100 g · 48 g KH", so the name
/// keeps the width up to the counter. A food the model counted in pieces
/// carries a "− 4 +" counter at the right: a miscounted plate is corrected
/// through [onRecount] with one tap instead of another photo. It never goes
/// below one piece.
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
    final items = estimate.summary(
      Locales.string(context, 'injection.photo.other'),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, colors),
          for (final (index, item) in items.indexed) ...[
            if (index > 0) Divider(height: 1, color: colors.border),
            _PhotoFoodRow(item: item, onRecount: onRecount),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, InsulinkColors colors) {
    final carbs = Locales.string(
      context,
      'injection.photo.carbs',
      params: [sportDecimal(estimate.carbs, 0)],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        spacing: 6,
        children: [
          Icon(PhosphorIconsRegular.camera, size: 16, color: colors.muted),
          Expanded(
            child: Text(
              carbs,
              style: InkText.caption.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One food: its name over "100 g · 48 g KH", and the counter at the right
/// when the model counted it in pieces.
class _PhotoFoodRow extends StatelessWidget {
  const _PhotoFoodRow({required this.item, required this.onRecount});

  final PhotoEstimateItem item;
  final void Function(PhotoEstimateItem item, int count) onRecount;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final carbsUnit = Locales.string(context, 'nutrition.food.carbs');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(item.name, style: InkText.row),
                Text(
                  '${sportDecimal(item.grams, 0)} g · '
                  '${sportDecimal(item.carbs, 0)} g $carbsUnit',
                  style: InkText.caption.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          if (item.countable) _counter(),
        ],
      ),
    );
  }

  Widget _counter() {
    return StepperPill(
      value: '${item.count}',
      onMinus: item.count > 1 ? () => onRecount(item, item.count - 1) : null,
      onPlus: () => onRecount(item, item.count + 1),
      minusLabelKey: 'injection.photo.fewer',
      plusLabelKey: 'injection.photo.more',
    );
  }
}
