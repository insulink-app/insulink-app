import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/overview/overview_section.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:provider/provider.dart';

/// Active insulin (IOB) on the overview: the units still working from recent
/// boluses and when the last of them wears off. Renders nothing while no dose is
/// active, so the section only appears when it has something to say.
///
/// The value decays continuously, but [MealState] only notifies on a new meal —
/// so this ticks itself once a minute to keep the number honest even when no
/// reading arrives. It owns its section wrapper + trailing gap because it is
/// conditional: hiding it must leave no empty card and no stray spacing.
class OverviewActiveInsulin extends StatefulWidget {
  const OverviewActiveInsulin({super.key});

  @override
  State<OverviewActiveInsulin> createState() => _OverviewActiveInsulinState();
}

class _OverviewActiveInsulinState extends State<OverviewActiveInsulin> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    final insulin = ActiveInsulin(
      context.watch<ProfileBolusState>().insulinDuration,
    );
    final units = insulin.units(meals);
    if (units <= 0) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        OverviewSection(child: _content(context, units, insulin, meals)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    double units,
    ActiveInsulin insulin,
    List<Meal> meals,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final until = insulin.activeUntil(meals);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LocaleText(
                'overview.active_insulin',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (until != null) ...[
                const SizedBox(height: 6),
                Text(
                  Locales.string(
                    context,
                    'overview.active_insulin.until',
                    params: [TimeOfDay.fromDateTime(until).format(context)],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Sized to span the label + "active until" stack beside it, so the
        // number reads as the section's headline. onSurface, not a literal
        // white: it reads white on the dark theme and stays legible on the light
        // one, where white on white would be invisible.
        Text(
          Locales.string(
            context,
            'injection.bolus.value',
            params: [units.toStringAsFixed(1)],
          ),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            height: 1,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
