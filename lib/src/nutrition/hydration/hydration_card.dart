import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/nutrition/hydration/drink_add_row.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/hydration/today_drinks_sheet.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Top section of the nutrition page: a "Trinken" header with a settings button
/// outside the card (room for more settings), then a box with today's intake
/// against the goal, a log button (opens today's drinks to review/remove), and
/// the one-tap drink picker.
class HydrationCard extends StatelessWidget {
  const HydrationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NutritionState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          titleKey: 'nutrition.hydration',
          topGap: 0,
          actions: [
            HeaderIconButton.plain(
              icon: PhosphorIconsBold.clockCounterClockwise,
              labelKey: 'nutrition.hydration.log',
              onTap: () => showTodayDrinksSheet(context),
            ),
          ],
        ),
        InkPanel(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _amount(context, state),
              const SizedBox(height: 14),
              TrackBar(
                startFraction: 0,
                endFraction: state.todayFraction,
                color: context.ink.accent,
                height: 6,
              ),
              const SizedBox(height: 18),
              DrinkAddRow(state: state),
            ],
          ),
        ),
      ],
    );
  }

  /// Today's total large, the goal small and muted beside it.
  Widget _amount(BuildContext context, NutritionState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: 8,
      children: [
        Text(
          '${formatLitres(state.todayMl / 1000)} L',
          style: InkText.bigValue.copyWith(fontSize: 34),
        ),
        Text(
          Locales.string(
            context,
            'nutrition.hydration.of',
            params: ['${formatLitres(state.goalLitres)} L'],
          ),
          style: InkText.label.copyWith(color: context.ink.muted),
        ),
      ],
    );
  }
}
