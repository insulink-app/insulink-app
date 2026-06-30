import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/sport/weight/weight_chart.dart';
import 'package:insulink/src/sport/weight/weight_entry_row.dart';
import 'package:insulink/src/sport/weight/weight_entry_sheet.dart';
import 'package:provider/provider.dart';

/// Gewichtsverlauf: aktueller Wert, Chart und die Einträge (neueste zuerst).
/// „+" öffnet das Eingabe-Sheet.
class WeightDetailPage extends StatelessWidget {
  const WeightDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sport = context.watch<SportState>();
    final weights = sport.weights;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.weight'),
      ),
      floatingActionButton: FloatingActionButton(
        // Eigener heroTag, sonst fliegt der FAB beim Öffnen aus dem zentralen
        // Injection-Button hierher (gemeinsamer Default-FAB-Hero-Tag).
        heroTag: 'weight-add',
        onPressed: () => showWeightEntrySheet(context),
        child: const Icon(Icons.add),
      ),
      body: weights.isEmpty
          ? Center(child: LocaleText('sport.weight.empty'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                _CurrentCard(weights: weights),
                const SizedBox(height: 24),
                _ChartCard(weights: weights),
                const SizedBox(height: 24),
                LocaleText(
                  'sport.weight.history',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (var index = weights.length - 1; index >= 0; index--)
                  WeightEntryRow(
                    entry: weights[index],
                    previousKg: index > 0 ? weights[index - 1].kg : null,
                    onDelete: () => sport.removeWeight(weights[index]),
                  ),
              ],
            ),
    );
  }
}

/// Hervorgehobener Kopf mit dem aktuellen Gewicht + Veränderung.
class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.weights});

  final List<WeightEntry> weights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = weights.last;
    final delta =
        weights.length >= 2 ? latest.kg - weights[weights.length - 2].kg : null;
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
            'sport.weight.current',
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
                latest.kg.toStringAsFixed(1),
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              Text(
                'kg',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              if (delta != null && delta != 0) WeightDeltaChip(delta: delta),
            ],
          ),
        ],
      ),
    );
  }
}

/// Der Verlaufs-Chart in einer abgerundeten Karte.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.weights});

  final List<WeightEntry> weights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: SizedBox(height: 200, child: WeightChart(weights: weights)),
    );
  }
}
