import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/hydration/free_drink_sheet.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

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
          PhosphorIconsRegular.plus,
          Locales.string(context, 'nutrition.hydration.free'),
          () => _free(context),
        ),
      ],
    );
  }

  void _add(int ml, String kind) {
    HapticFeedback.selectionClick();
    state.addDrink(ml, kind);
  }

  Widget _button(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(icon, color: scheme.onPrimary, size: 22),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
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
