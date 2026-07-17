import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/hydration/drink_add_row.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/hydration/today_drinks_sheet.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Top section of the nutrition page: a "Trinken" header with a settings button
/// outside the card (room for more settings), then a box with today's intake
/// against the goal, a log button (opens today's drinks to review/remove), and
/// the one-tap drink picker.
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
    return LocaleText(
      'nutrition.hydration',
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
          _topRow(context, state, accent),
          const SizedBox(height: 8),
          TrackBar(
            startFraction: 0,
            endFraction: state.todayFraction,
            color: accent,
          ),
          const SizedBox(height: 16),
          DrinkAddRow(state: state),
        ],
      ),
    );
  }

  /// Today's total on the left, the log button (review/remove drinks) on the
  /// right.
  Widget _topRow(BuildContext context, NutritionState state, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _amount(context, state, accent)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            PhosphorIconsBold.clockCounterClockwise,
            size: 22,
          ),
          onPressed: () => showTodayDrinksSheet(context),
        ),
      ],
    );
  }

  Widget _amount(BuildContext context, NutritionState state, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${formatLitres(state.todayMl / 1000)} L',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 6),
        Text(
          '/ ${formatLitres(state.goalLitres)} L',
          style: TextStyle(
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
