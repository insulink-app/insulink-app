import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/hydration/free_drink_sheet.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The one-tap drink picker: the size presets (smallest→largest) followed by a
/// free amount entry. Each is an icon over a single-line amount, so the buttons
/// stay the same height regardless of label length.
class DrinkAddRow extends StatelessWidget {
  const DrinkAddRow({super.key, required this.state});

  final NutritionState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final preset in drinkPresets)
          _button(
            context,
            preset.icon,
            preset.amountLabel,
            () => _add(preset.ml, preset.kind),
          ),
        _button(
          context,
          PhosphorIconsBold.plus,
          Locales.string(context, 'nutrition.hydration.free'),
          () => _free(context),
          open: true,
        ),
      ],
    );
  }

  void _add(int ml, String kind) {
    HapticFeedback.selectionClick();
    state.addDrink(ml, kind);
  }

  /// A 52 px disc, accent glyph on a soft accent face, the amount bold under
  /// it. The free entry is a dashed ring instead, since it has no amount yet.
  Widget _button(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool open = false,
  }) {
    final colors = context.ink;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              spacing: 8,
              children: [
                SizedBox.square(
                  dimension: 52,
                  child: CustomPaint(
                    painter: open ? _DashedRing(colors.accent) : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: open
                            ? null
                            : colors.accent.withValues(alpha: 0.12),
                      ),
                      child: Icon(icon, color: colors.accent, size: 22),
                    ),
                  ),
                ),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InkText.caption.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Free entry: opens the amount sheet, then logs a `free` drink.
  Future<void> _free(BuildContext context) async {
    final ml = await showFreeDrinkSheet(context);
    if (ml != null && ml > 0) {
      HapticFeedback.selectionClick();
      state.addDrink(ml, 'free');
    }
  }
}

/// The dashed outline of the free-amount disc.
class _DashedRing extends CustomPainter {
  const _DashedRing(this.color);

  final Color color;

  static const int _dashes = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(1);
    const sweep = math.pi * 2 / _dashes;
    for (var index = 0; index < _dashes; index++) {
      canvas.drawArc(rect, index * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.color != color;
}
