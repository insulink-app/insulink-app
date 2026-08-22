import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/pump/pod_controller.dart';
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
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Runs the once-a-minute decay tick ONLY while a dose is active — an empty
  /// list is static, so ticking then would rebuild for nothing. A fresh bolus
  /// arrives via [MealState] notifying, which rebuilds and restarts the tick.
  void _syncTicker(bool active) {
    if (active && _tick == null) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    } else if (!active && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    final insulin = ActiveInsulin(
      context.watch<ProfileBolusState>().insulinDuration,
    );
    final doses = insulin.activeDoses(meals);
    final parts = _onBoard(context, meals);
    _syncTicker(doses.isNotEmpty || parts.beyondBoluses > 0);
    return Scaffold(
      appBar: AppBar(title: LocaleText('overview.active_insulin')),
      // Empty only when there is genuinely NO insulin working. The dose list can
      // be empty while the pump is still delivering above the schedule, and
      // saying "no active doses" there would deny insulin that is in the body.
      body: parts.total <= 0
          ? EmptyState(
              icon: PhosphorIconsBold.drop,
              titleKey: 'overview.active_insulin.empty',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 64),
              children: [
                _totalHeader(context, insulin, meals, parts),
                const SizedBox(height: 24),
                ..._curve(insulin, meals),
                LocaleText(
                  'overview.active_insulin.doses',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (doses.isEmpty) _noDosesNote(context),
                for (final dose in doses) _doseCard(context, insulin, dose),
                ..._pumpCard(context, parts),
              ],
            ),
    );
  }

  /// Everything on board, so this page agrees with the overview box that opened
  /// it and with the bolus calculator. Three screens showing one quantity have
  /// to show the same number.
  InsulinOnBoardParts _onBoard(BuildContext context, List<Meal> meals) {
    return InsulinOnBoard(
      context.watch<ProfileBolusState>().insulinDuration,
    ).parts(meals, pod: context.watch<PodController>().store);
  }

  /// The decay curve, drawn only when there is one.
  ///
  /// It is built from the meal log, so an insulin-on-board made up ENTIRELY of
  /// pump insulin leaves it empty. [ActiveInsulinChart] reads `points.first` and
  /// `points.last`, so an empty list threw during layout and left the grey
  /// 180-pixel box its failed render was sitting in. Two points are also the
  /// least that can be a line.
  List<Widget> _curve(ActiveInsulin insulin, List<Meal> meals) {
    final points = insulin.curve(meals);
    if (points.length < 2) {
      return const [];
    }
    return [
      SizedBox(
        height: 180,
        child: ActiveInsulinChart(points: points, now: DateTime.now()),
      ),
      const SizedBox(height: 24),
    ];
  }

  /// Says why the dose list is empty while the total is not.
  Widget _noDosesNote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LocaleText(
        'overview.active_insulin.no_doses',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// The pump's own share as its own entry, so the list adds up to the total
  /// above it. It is not a dose card: nobody chose it and there is nothing to
  /// tap through to.
  List<Widget> _pumpCard(BuildContext context, InsulinOnBoardParts parts) {
    if (parts.beyondBoluses <= 0.05) {
      return const [];
    }
    final scheme = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsBold.repeat, size: 18,
                color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: LocaleText(
                'overview.active_insulin.from_pump',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              Locales.string(
                context,
                'injection.bolus.value',
                params: [parts.beyondBoluses.toStringAsFixed(2)],
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _totalHeader(
    BuildContext context,
    ActiveInsulin insulin,
    List<Meal> meals,
    InsulinOnBoardParts parts,
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
            params: [parts.total.toStringAsFixed(1)],
          ),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
        ),
        // The dose list below is the meal log, so a total larger than it needs
        // saying where the rest came from.
        if (parts.beyondBoluses > 0.05) ...[
          const SizedBox(height: 2),
          Text(
            Locales.string(
              context,
              'injection.active_insulin_pump',
              params: [parts.beyondBoluses.toStringAsFixed(1)],
            ),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
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
