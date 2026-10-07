import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/weight/weight_chart.dart';
import 'package:insulink/src/sport/weight/weight_current_card.dart';
import 'package:insulink/src/sport/weight/weight_entry_row.dart';
import 'package:insulink/src/sport/weight/weight_entry_sheet.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/stat_strip.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Weight history: current value + range metrics, chart with range picker and
/// the entries (newest first). "+" opens the sheet.
class WeightDetailPage extends StatefulWidget {
  const WeightDetailPage({super.key});

  @override
  State<WeightDetailPage> createState() => _WeightDetailPageState();
}

class _WeightDetailPageState extends State<WeightDetailPage> {
  SportRange _range = const SportRange.preset(90);

  static const int _page = 8;

  /// How many history rows are shown; "show more" adds a page.
  int _shown = _page;

  List<WeightEntry> _inRange(List<WeightEntry> all) {
    final now = DateTime.now();
    final from = _range.startFrom(now);
    final to = _range.endTo;
    return [
      for (final entry in all)
        if ((from == null || !entry.time.isBefore(from)) &&
            (to == null || entry.time.isBefore(to)))
          entry,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final weights = context.watch<SportState>().weights;
    final ranged = _inRange(weights);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.weight'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'weight-add',
        onPressed: () => showWeightEntrySheet(context),
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: weights.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsBold.scales,
              titleKey: 'sport.weight.empty',
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
              children: [
                WeightCurrentCard(
                  latest: weights.last,
                  previousKg: weights.length >= 2
                      ? weights[weights.length - 2].kg
                      : null,
                  bmi: context.watch<SportState>().bmi,
                ),
                if (ranged.length >= 2) ...[
                  const SizedBox(height: 18),
                  _stats(context, ranged),
                ],
                const SizedBox(height: 18),
                SportRangeSelector(
                  value: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 10),
                _chartCard(context, ranged),
                ..._history(context, ranged),
              ],
            ),
    );
  }

  double _average(List<WeightEntry> ranged) =>
      ranged.map((entry) => entry.kg).reduce((sum, kg) => sum + kg) /
      ranged.length;

  /// Min, Ø and Max over the window.
  Widget _stats(BuildContext context, List<WeightEntry> ranged) {
    final values = ranged.map((entry) => entry.kg);
    MetricCell cell(String key, double kg) => (
      label: Locales.string(context, key),
      value: sportDecimal(kg, 1),
      unit: 'kg',
    );
    return StatStrip(
      cells: [
        cell(
          'sport.weight.min',
          values.reduce((low, kg) => low < kg ? low : kg),
        ),
        cell('sport.weight.avg', _average(ranged)),
        cell(
          'sport.weight.max',
          values.reduce((high, kg) => high > kg ? high : kg),
        ),
      ],
    );
  }

  Widget _chartCard(BuildContext context, List<WeightEntry> ranged) {
    final colors = context.ink;
    final average = ranged.isEmpty ? null : _average(ranged);
    return InkPanel(
      padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (average != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                spacing: 10,
                children: [
                  Row(
                    spacing: 2,
                    children: [
                      for (var dash = 0; dash < 4; dash++)
                        Container(width: 3, height: 1.5, color: colors.accent),
                    ],
                  ),
                  Text(
                    Locales.string(
                      context,
                      'google_health.sleep_page.average',
                      params: ['${sportDecimal(average, 1)} kg'],
                    ),
                    style: InkText.caption.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            height: 220,
            child: ranged.isEmpty
                ? Center(child: LocaleText('sport.weight.empty'))
                : WeightChart(
                    weights: ranged,
                    goalKg: context.watch<SportState>().weightGoalKg,
                    averageKg: average,
                  ),
          ),
        ],
      ),
    );
  }

  /// The entries newest first, in one panel, a page at a time.
  List<Widget> _history(BuildContext context, List<WeightEntry> ranged) {
    if (ranged.isEmpty) {
      return const [];
    }
    final visible = ranged.reversed.take(_shown).toList();
    return [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SectionHeader(titleKey: 'sport.weight.history'),
      ),
      InkPanel.list(
        rows: [
          for (final entry in visible)
            WeightEntryRow(
              entry: entry,
              framed: false,
              previousKg: _previous(ranged, entry),
              onDelete: () => context.read<SportState>().removeWeight(entry),
              onEdit: () => showWeightEntrySheet(context, existing: entry),
            ),
        ],
      ),
      if (ranged.length > _shown)
        TextButton(
          onPressed: () => setState(() => _shown += _page),
          child: LocaleText('nutrition.meals.show_more'),
        ),
    ];
  }

  double? _previous(List<WeightEntry> ranged, WeightEntry entry) {
    final index = ranged.indexOf(entry);
    return index > 0 ? ranged[index - 1].kg : null;
  }
}
