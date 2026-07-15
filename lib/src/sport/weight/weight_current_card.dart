import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/weight/weight_entry_row.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/brand_tints.dart';

/// Highlighted "Current" box: current weight + trend, with min/avg/max of the
/// selected range below. [ranged] are the entries in the selected window,
/// [latest] is always the newest overall value.
class WeightCurrentCard extends StatelessWidget {
  const WeightCurrentCard({
    super.key,
    required this.latest,
    required this.previousKg,
    required this.ranged,
    this.bmi,
  });

  final WeightEntry latest;
  final double? previousKg;
  final List<WeightEntry> ranged;

  /// Body-mass index (from the stored height), shown as a pill when available.
  final double? bmi;

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
                sportDecimal(latest.kg, 1),
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'kg',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (bmi != null) ...[
                const SizedBox(width: 12),
                _bmiPill(context, scheme),
              ],
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

  Widget _bmiPill(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.tintPanel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${Locales.string(context, 'sport.weight.bmi')} ${sportDecimal(bmi!, 1)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
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
        _stat(
          context,
          scheme,
          PhosphorIconsRegular.arrowDown,
          'sport.weight.min',
          min,
        ),
        _stat(
          context,
          scheme,
          PhosphorIconsRegular.chartLine,
          'sport.weight.avg',
          avg,
        ),
        _stat(
          context,
          scheme,
          PhosphorIconsRegular.arrowUp,
          'sport.weight.max',
          max,
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    ColorScheme scheme,
    IconData icon,
    String labelKey,
    double kg,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
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
              '${sportDecimal(kg, 1)} kg',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
