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

/// Weight history: current value + range metrics, chart with range picker and
/// the entries (newest first). "+" opens the sheet.
class WeightDetailPage extends StatefulWidget {
  const WeightDetailPage({super.key});

  @override
  State<WeightDetailPage> createState() => _WeightDetailPageState();
}

class _WeightDetailPageState extends State<WeightDetailPage> {
  SportRange _range = const SportRange.preset(90);

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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                WeightCurrentCard(
                  latest: weights.last,
                  previousKg: weights.length >= 2
                      ? weights[weights.length - 2].kg
                      : null,
                  ranged: ranged,
                  bmi: context.watch<SportState>().bmi,
                ),
                const SizedBox(height: 20),
                SportRangeSelector(
                  value: _range,
                  onChanged: (range) => setState(() => _range = range),
                ),
                const SizedBox(height: 16),
                _chartCard(context, ranged),
                const SizedBox(height: 24),
                LocaleText(
                  'sport.weight.history',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = ranged.length - 1; index >= 0; index--)
                  WeightEntryRow(
                    entry: ranged[index],
                    previousKg: index > 0 ? ranged[index - 1].kg : null,
                    onDelete: () =>
                        context.read<SportState>().removeWeight(ranged[index]),
                    onEdit: () => showWeightEntrySheet(
                      context,
                      existing: ranged[index],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _chartCard(BuildContext context, List<WeightEntry> ranged) {
    final scheme = Theme.of(context).colorScheme;
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
            ? Center(child: LocaleText('sport.weight.empty'))
            : WeightChart(
                weights: ranged,
                goalKg: context.watch<SportState>().weightGoalKg,
              ),
      ),
    );
  }
}
