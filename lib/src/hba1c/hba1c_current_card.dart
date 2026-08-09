import 'package:flutter/material.dart';
import 'package:insulink/src/base/measurement_row.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// Header of the HbA1c page: the newest result big, the change against the one
/// before it, and the two figures every lab report prints next to it — the same
/// value in IFCC mmol/mol and the estimated average glucose it corresponds to.
/// Both are pure functions of the percentage (see [Hba1cEntry]), so they are
/// derived here rather than stored or entered.
class Hba1cCurrentCard extends StatelessWidget {
  const Hba1cCurrentCard({super.key, required this.latest, this.previous});

  final Hba1cEntry latest;
  final Hba1cEntry? previous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = previous == null ? null : latest.percent - previous!.percent;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${sportDecimal(latest.percent, 1)} %',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(width: 12),
              if (delta != null && delta != 0)
                MeasurementDeltaChip(delta: delta, unit: '%'),
            ],
          ),
          const SizedBox(height: 10),
          _fact(
            context,
            'hba1c.mmol_per_mol',
            '${sportDecimal(latest.mmolPerMol, 0)} mmol/mol',
          ),
          _fact(
            context,
            'hba1c.average_glucose',
            '${sportDecimal(latest.averageGlucoseMgDl, 0)} mg/dL',
          ),
          _fact(
            context,
            'hba1c.measured_at',
            '${latest.time.day}.${latest.time.month}.${latest.time.year}',
          ),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, String labelKey, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            Locales.string(context, labelKey),
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
