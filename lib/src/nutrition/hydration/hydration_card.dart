import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/hydration/drink_add_row.dart';
import 'package:insulink/src/nutrition/hydration/hydration_settings_sheet.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:provider/provider.dart';

/// Top section of the nutrition page: a "Trinken" header with a settings button
/// outside the card (room for more settings), then a box with today's intake
/// against the goal, the one-tap drink picker, and the drinks logged today
/// (each with its time; tap a chip to remove a mistap).
class HydrationCard extends StatelessWidget {
  const HydrationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionState>();
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context),
        const SizedBox(height: 12),
        _box(context, state, accent),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'nutrition.hydration',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => showHydrationSettingsSheet(context),
        ),
      ],
    );
  }

  Widget _box(BuildContext context, NutritionState state, Color accent) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _amount(state, accent),
          const SizedBox(height: 8),
          TrackBar(
            startFraction: 0,
            endFraction: state.todayFraction,
            color: accent,
          ),
          const SizedBox(height: 16),
          DrinkAddRow(state: state),
          if (state.todayEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            _todayDrinks(state, accent),
          ],
        ],
      ),
    );
  }

  Widget _amount(NutritionState state, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${formatLitres(state.todayMl / 1000)} L',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '/ ${formatLitres(state.goalLitres)} L',
          style: TextStyle(fontSize: 15, color: Colors.grey[600]),
        ),
      ],
    );
  }

  /// Drinks logged today as removable chips, newest first (tap the × to delete a
  /// mistap). The logging time is persisted on each entry but not shown.
  Widget _todayDrinks(NutritionState state, Color accent) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in state.todayEntries.reversed)
          InputChip(
            avatar: Icon(iconForKind(entry.kind), size: 18, color: accent),
            label: Text('${entry.ml} ml'),
            onDeleted: () => state.removeEntry(entry),
            backgroundColor: accent.withValues(alpha: 0.06),
            side: BorderSide.none,
          ),
      ],
    );
  }
}
