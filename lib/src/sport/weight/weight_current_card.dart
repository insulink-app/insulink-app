import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/weight/weight_entry_row.dart';

/// Hervorgehobene „Aktuell"-Box: aktuelles Gewicht + Trend, darunter Min/Ø/Max
/// des gewählten Zeitraums. [ranged] sind die Einträge im gewählten Fenster,
/// [latest] ist stets der neueste Gesamtwert.
class WeightCurrentCard extends StatelessWidget {
  const WeightCurrentCard({
    super.key,
    required this.latest,
    required this.previousKg,
    required this.ranged,
  });

  final WeightEntry latest;
  final double? previousKg;
  final List<WeightEntry> ranged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = previousKg == null ? null : latest.kg - previousKg!;
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
            style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                latest.kg.toStringAsFixed(1),
                style: const TextStyle(fontSize: 46, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              Text('kg', style: TextStyle(fontSize: 16, color: scheme.onSurface.withValues(alpha: 0.6))),
              const Spacer(),
              if (delta != null && delta != 0) WeightDeltaChip(delta: delta),
            ],
          ),
          if (ranged.length >= 2) ...[
            const SizedBox(height: 18),
            Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 16),
            _stats(context, scheme),
          ],
        ],
      ),
    );
  }

  Widget _stats(BuildContext context, ColorScheme scheme) {
    final values = ranged.map((entry) => entry.kg);
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / ranged.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _stat(context, scheme, Icons.south_rounded, 'sport.weight.min', min),
        _stat(context, scheme, Icons.timeline_rounded, 'sport.weight.avg', avg),
        _stat(context, scheme, Icons.north_rounded, 'sport.weight.max', max),
      ],
    );
  }

  Widget _stat(BuildContext context, ColorScheme scheme, IconData icon, String labelKey, double kg) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Locales.string(context, labelKey),
              style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 1),
            Text(
              '${kg.toStringAsFixed(1)} kg',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
