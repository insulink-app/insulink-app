import 'package:flutter/material.dart';
import 'package:insulink/src/base/stepper_pill.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One food the photo estimate saw: its name over "100 g · 48 g KH", so the
/// name keeps the width up to the right edge. A food the model counted in
/// pieces carries a "− 4 +" counter there: a miscounted plate is corrected
/// through [onRecount] with one tap instead of another photo, never below one
/// piece. Otherwise [trailing] sits there, if given.
class PhotoFoodRow extends StatelessWidget {
  const PhotoFoodRow({
    super.key,
    required this.item,
    required this.onRecount,
    this.trailing,
  });

  final PhotoEstimateItem item;
  final void Function(PhotoEstimateItem item, int count) onRecount;
  final Widget? trailing;

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
          if (item.countable) _counter() else ?trailing,
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
