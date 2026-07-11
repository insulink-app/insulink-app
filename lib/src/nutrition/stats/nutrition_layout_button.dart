import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/tile_layout_editor.dart';
import 'package:provider/provider.dart';

/// Card inside the nutrition settings sheet that opens the box-layout editor
/// (show/hide + reorder the stats boxes). Mirrors the Sport tab's layout button.
class NutritionLayoutButton extends StatelessWidget {
  const NutritionLayoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  color: scheme.onPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LocaleText(
                      'sport.layout.title',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    LocaleText(
                      'sport.layout.subtitle',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final state = context.read<NutritionLayoutState>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TileLayoutEditor<NutritionTile>(
          state: state,
          titleKey: 'sport.layout.title',
          hintKey: 'sport.layout.hint',
          icon: nutritionTileIcon,
          labelKey: nutritionTileLabelKey,
        ),
      ),
    );
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
  }
}
