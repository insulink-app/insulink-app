import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:provider/provider.dart';

/// One day's aggregated value of a nutrition box.
class _NutritionDay {
  final DateTime date;
  final double value;

  const _NutritionDay(this.date, this.value);
}

/// History of a nutrition box: a header (latest / average / total), a bar chart
/// with range picker and a day list. Mirrors the Sport tab's activity detail
/// page and reuses its chart + range selector. Reached by tapping a stat box.
class NutritionDetailPage extends StatefulWidget {
  const NutritionDetailPage({super.key, required this.tile});

  final NutritionTile tile;

  @override
  State<NutritionDetailPage> createState() => _NutritionDetailPageState();
}

class _NutritionDetailPageState extends State<NutritionDetailPage> {
  SportRange _range = const SportRange.preset(30);

  NutritionTile get _tile => widget.tile;

  /// All days that have data, ascending, aggregated for the current box.
  List<_NutritionDay> _series(MealState meals, NutritionState hydration) {
    final byDay = <DateTime, double>{};
    if (_tile == NutritionTile.water) {
      for (final entry in hydration.entries) {
        final day = _dayOf(DateTime.fromMillisecondsSinceEpoch(entry.atEpochMs));
        byDay[day] = (byDay[day] ?? 0) + entry.ml / 1000;
      }
    } else {
      for (final meal in meals.meals) {
        final day = _dayOf(meal.time);
        byDay[day] = (byDay[day] ?? 0) + _mealValue(meal);
      }
    }
    final days = [
      for (final entry in byDay.entries) _NutritionDay(entry.key, entry.value),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return days;
  }

  double _mealValue(Meal meal) => switch (_tile) {
    NutritionTile.carbs => meal.carbs,
    NutritionTile.protein => meal.protein,
    NutritionTile.bolus => meal.bolus,
    NutritionTile.meals => 1.0,
    NutritionTile.water => 0.0,
  };

  DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<_NutritionDay> _inRange(List<_NutritionDay> all) {
    final now = DateTime.now();
    final from = _range.startFrom(now);
    final to = _range.endTo;
    return [
      for (final day in all)
        if ((from == null ||
                !day.date.isBefore(DateTime(from.year, from.month, from.day))) &&
            (to == null || day.date.isBefore(to)))
          day,
    ];
  }

  String? get _unit => switch (_tile) {
    NutritionTile.carbs => 'g',
    NutritionTile.protein => 'g',
    NutritionTile.bolus => 'E',
    NutritionTile.water => 'L',
    NutritionTile.meals => null,
  };

  String _format(double value) => switch (_tile) {
    NutritionTile.bolus => value.toStringAsFixed(1),
    NutritionTile.water => formatLitres(value),
    _ => value.toStringAsFixed(0),
  };

  String _formatWithUnit(double value) =>
      _unit == null ? _format(value) : '${_format(value)} $_unit';

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>();
    final hydration = context.watch<NutritionState>();
    final all = _series(meals, hydration);
    final ranged = _inRange(all);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(nutritionTileLabelKey(_tile)),
      ),
      body: all.isEmpty
          ? const EmptyState(
              icon: Icons.insights_rounded,
              titleKey: 'nutrition.meals.empty',
              subtitleKey: 'nutrition.meals.empty_hint',
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                _header(context, scheme, ranged),
                const SizedBox(height: 20),
                SportRangeSelector(
                  value: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 16),
                _chartCard(scheme, ranged),
                const SizedBox(height: 24),
                LocaleText(
                  'nutrition.detail.history',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = ranged.length - 1; index >= 0; index--)
                  _dayRow(context, scheme, ranged[index]),
              ],
            ),
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    List<_NutritionDay> ranged,
  ) {
    final total = ranged.fold<double>(0, (sum, day) => sum + day.value);
    final avg = ranged.isEmpty ? 0.0 : total / ranged.length;
    final latest = ranged.isEmpty ? 0.0 : ranged.last.value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            'nutrition.detail.latest',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _format(latest),
                style:
                    const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              ),
              if (_unit != null) ...[
                const SizedBox(width: 6),
                Text(
                  _unit!,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(context, scheme, Icons.timeline_rounded,
                  'nutrition.detail.average', avg),
              _stat(context, scheme, Icons.functions_rounded,
                  'nutrition.detail.total', total),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    ColorScheme scheme,
    IconData icon,
    String labelKey,
    double value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Locales.string(context, labelKey),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _formatWithUnit(value),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chartCard(ColorScheme scheme, List<_NutritionDay> ranged) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: SizedBox(
        height: 200,
        child: ranged.isEmpty
            ? Center(child: LocaleText('nutrition.meals.empty'))
            : ActivityBarChart<_NutritionDay>(
                days: ranged,
                date: (day) => day.date,
                value: (day) => day.value,
                label: (day) => _formatWithUnit(day.value),
                color: scheme.primary,
              ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, ColorScheme scheme, _NutritionDay day) {
    final locale = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              locale.formatMediumDate(day.date),
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            Text(
              _formatWithUnit(day.value),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
