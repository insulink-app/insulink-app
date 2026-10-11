import 'package:flutter/material.dart';
import 'package:insulink/src/base/measurement_row.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:intl/intl.dart';

/// The newest result at the top of the page, open without a card like the
/// weight page: when it was measured, the value large and the change against
/// the one before it on the right.
class Hba1cCurrentCard extends StatelessWidget {
  const Hba1cCurrentCard({super.key, required this.latest, this.previous});

  final Hba1cEntry latest;
  final Hba1cEntry? previous;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final delta = previous == null ? null : latest.percent - previous!.percent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _measuredAt(context),
            style: InkText.label.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                sportDecimal(latest.percent, 1),
                style: InkText.bigValue.copyWith(
                  fontSize: 56,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 8),
              Text('%', style: InkText.section.copyWith(color: colors.muted)),
              const Spacer(),
              if (delta != null && delta != 0)
                MeasurementDeltaChip(delta: delta, unit: '%'),
            ],
          ),
        ],
      ),
    );
  }

  String _measuredAt(BuildContext context) {
    final tag = Localizations.localeOf(context).toLanguageTag();
    return '${Locales.string(context, 'hba1c.measured_at')} '
        '${DateFormat.yMMMd(tag).format(latest.time)}';
  }
}
