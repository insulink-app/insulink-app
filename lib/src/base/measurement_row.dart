import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Small pill badge for the change against the previous entry.
///
/// [risingIsBad] flips which direction is coloured as a warning: for weight and
/// HbA1c alike a rise is the unwelcome one, but the flag stays explicit so a
/// future metric where more is better doesn't have to invert its own values to
/// get the right colour.
class MeasurementDeltaChip extends StatelessWidget {
  const MeasurementDeltaChip({
    super.key,
    required this.delta,
    required this.unit,
    this.decimals = 1,
    this.risingIsBad = true,
  });

  final double delta;
  final String unit;
  final int decimals;
  final bool risingIsBad;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final bad = up == risingIsBad;
    final color = bad ? context.warning : context.positive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? PhosphorIconsBold.arrowUp : PhosphorIconsBold.arrowDown,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${sportDecimal(delta.abs(), decimals)} $unit',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row in a measurement history: value + date, the change from the previous
/// entry, and delete. Tapping the row edits it.
class MeasurementRow extends StatelessWidget {
  const MeasurementRow({
    super.key,
    required this.value,
    required this.time,
    required this.unit,
    required this.deleteConfirmKey,
    required this.onDelete,
    required this.onEdit,
    this.previous,
    this.decimals = 1,
  });

  final double value;
  final DateTime time;
  final String unit;

  /// The preceding entry's value, for the delta chip. Null on the oldest row.
  final double? previous;
  final int decimals;

  /// Localization key for the delete confirmation message.
  final String deleteConfirmKey;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = previous == null ? null : value - previous!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(child: _valueAndDate(context, scheme)),
              if (delta != null && delta != 0)
                MeasurementDeltaChip(
                  delta: delta,
                  unit: unit,
                  decimals: decimals,
                ),
              IconButton(
                icon: const Icon(PhosphorIconsBold.trash, size: 20),
                onPressed: () => confirmDelete(
                  context,
                  messageKey: deleteConfirmKey,
                  onConfirm: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _valueAndDate(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${sportDecimal(value, decimals)} $unit',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${Locales.string(context, 'date.weekday.${time.weekday}')} '
          '${time.day}.${time.month}.${time.year}',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
