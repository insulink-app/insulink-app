import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/injection/insulin_on_board.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/injection/active_insulin_sparkline.dart';
import 'package:insulink/src/injection/active_insulin_page.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// The insulin summary on the overview: the units still working from recent
/// boluses as the headline, the IOB curve underneath as a sparkline, and one
/// muted line naming the last dose and when the insulin runs out. Renders nothing
/// while no dose is active, so the section only appears when it has something to
/// say.
///
/// The curve carries what two lines of grey text used to spell out — how fast it
/// is falling and how much is left — which is why there is only one caption line
/// now instead of a paragraph of them.
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
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Runs the once-a-minute decay tick ONLY while a dose is active — with no
  /// insulin on board (the common case) the number is static, so ticking then
  /// would rebuild for nothing. A fresh bolus arrives via [MealState] notifying,
  /// which rebuilds and restarts the tick.
  void _syncTicker(bool active) {
    if (active && _tick == null) {
      _tick = Timer.periodic(
        const Duration(minutes: 1),
        (_) => setState(() {}),
      );
    } else if (!active && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshPumpInsulin();
  }

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    final duration = context.watch<ProfileBolusState>().insulinDuration;
    final insulin = ActiveInsulin(duration);
    final parts = InsulinOnBoard(
      duration,
    ).parts(meals, pod: context.watch<PodController>().store);
    final units = parts.total;
    _syncTicker(units > 0);
    if (units <= 0) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ActiveInsulinPage()),
          ),
          child: InkPanel(child: _content(context, parts, insulin, meals)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Re-reads the pod store once when the box appears.
  ///
  /// The automation runs in the background service isolate and the store serves
  /// its getters from a cache that is per isolate, so without this the overview
  /// would show whatever automated insulin this isolate knew about at app start.
  Future<void> _refreshPumpInsulin() async {
    await context.read<PodController>().store.reload();
    if (mounted) {
      setState(() {});
    }
  }

  Widget _content(
    BuildContext context,
    InsulinOnBoardParts parts,
    ActiveInsulin insulin,
    List<Meal> meals,
  ) {
    final now = DateTime.now();
    // Newest dose still on board. activeDoses is already sorted newest-first and
    // drops meals logged without a bolus, so the first entry is the last real
    // injection — no separate scan of the meal log.
    final doses = insulin.activeDoses(meals, now: now);
    final lastDose = doses.isEmpty ? null : doses.first.meal;
    // 10-minute sampling, not the detail page's 5: at 44 px tall the extra
    // vertices are invisible and this runs on every overview build.
    final curve = insulin.curve(
      meals,
      now: now,
      step: const Duration(minutes: 10),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _headline(context, parts.total),
        if (curve.length >= 2) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ActiveInsulinSparkline(points: curve, now: now),
          ),
        ],
        if (lastDose != null) ...[
          const SizedBox(height: 8),
          Text(
            Locales.string(
              context,
              'overview.active_insulin.summary',
              params: [
                _units(context, lastDose.bolus),
                TimeOfDay.fromDateTime(lastDose.time).format(context),
              ],
            ),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Section title on the left, the units on board on the right — the one number
  /// that carries the box, so it stays the only large thing in it.
  ///
  /// Top-aligned with both lines at height 1: in this font the capitals and
  /// digits then start ~0.08 em below each text box, so the title's top edge
  /// lines up with the number's within a pixel.
  Widget _headline(BuildContext context, double units) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LocaleText(
            'overview.active_insulin.title',
            style: InkText.section.copyWith(height: 1),
          ),
        ),
        Text(_units(context, units), style: InkText.bigValue),
      ],
    );
  }

  String _units(BuildContext context, double units) => Locales.string(
    context,
    'injection.bolus.value',
    params: [sportDecimal(units, 1)],
  );
}
