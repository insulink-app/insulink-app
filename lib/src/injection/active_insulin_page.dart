import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/injection/active_insulin_chart.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_detail_sheet.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/meal/meal_time.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Breaks the overview's single active-insulin number down into the individual
/// doses still working, so the user can see WHICH meals' boluses make it up and
/// open any of them. Opened by tapping the overview's active-insulin section.
///
/// Like the overview section it ticks itself once a minute so the decaying
/// per-dose units stay honest without waiting for a new meal.
class ActiveInsulinPage extends StatefulWidget {
  const ActiveInsulinPage({super.key});

  @override
  State<ActiveInsulinPage> createState() => _ActiveInsulinPageState();
}

class _ActiveInsulinPageState extends State<ActiveInsulinPage> {
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
    final doses = insulin.activeDoses(meals);
    return Scaffold(
      appBar: AppBar(title: LocaleText('overview.active_insulin')),
      body: doses.isEmpty
          ? EmptyState(
              icon: PhosphorIconsBold.drop,
              titleKey: 'overview.active_insulin.empty',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 64),
              children: [
                _totalHeader(context, insulin, meals),
                const SizedBox(height: 24),
                SizedBox(
                  height: 180,
                  child: ActiveInsulinChart(
                    points: insulin.curve(meals),
                    now: DateTime.now(),
                  ),
                ),
                const SizedBox(height: 24),
                LocaleText(
                  'overview.active_insulin.doses',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (final dose in doses) _doseCard(context, insulin, dose),
              ],
            ),
    );
  }

  Widget _totalHeader(
    BuildContext context,
    ActiveInsulin insulin,
    List<Meal> meals,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final until = insulin.activeUntil(meals);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          'overview.active_insulin.total',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          Locales.string(
            context,
            'injection.bolus.value',
            params: [insulin.units(meals).toStringAsFixed(1)],
          ),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
        ),
        if (until != null) ...[
          const SizedBox(height: 4),
          Text(
            Locales.string(
              context,
              'overview.active_insulin.until',
              params: [TimeOfDay.fromDateTime(until).format(context)],
            ),
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _doseCard(
    BuildContext context,
    ActiveInsulin insulin,
    ({Meal meal, double remaining}) dose,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = dose.meal.bolus <= 0
        ? 0.0
        : (dose.remaining / dose.meal.bolus).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showMealDetail(context, dose.meal),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mealTimeLabel(dose.meal.time),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      Locales.string(
                        context,
                        'overview.active_insulin.remaining',
                        params: [dose.remaining.toStringAsFixed(1)],
                      ),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  Locales.string(
                    context,
                    'overview.active_insulin.of_bolus',
                    params: [dose.meal.bolus.toStringAsFixed(1)],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(scheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
