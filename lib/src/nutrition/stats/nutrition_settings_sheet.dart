import 'package:flutter/material.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_goals_editor.dart';
import 'package:insulink/src/nutrition/stats/nutrition_layout_button.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:provider/provider.dart';

/// Unified nutrition settings: the daily carb / protein / water goals plus the
/// box-layout editor. Replaces the old hydration-only sheet — reached from the
/// single settings button in the stats header.
Future<void> showNutritionSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<NutritionState>.value(
      value: context.read<NutritionState>(),
      child: const _NutritionSettingsSheet(),
    ),
  );
  // Sync the (possibly changed) goals to the backend once editing is done.
  if (context.mounted) {
    await ProfileSettings().push(context);
  }
}

class _NutritionSettingsSheet extends StatelessWidget {
  const _NutritionSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return EditorSheet(
      titleKey: 'nutrition.settings',
      valueText: '',
      accent: accent,
      children: const [
        NutritionGoalsEditor(),
        SizedBox(height: 24),
        NutritionLayoutButton(),
      ],
    );
  }
}
