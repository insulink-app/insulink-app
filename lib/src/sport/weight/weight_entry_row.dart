import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Small pill badge for the weight change (green = lost, orange = gained). Also
/// used in the header of the weight page.
class WeightDeltaChip extends StatelessWidget {
  const WeightDeltaChip({super.key, required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color = up ? Colors.orange : Colors.green;
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
            up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${delta.abs().toStringAsFixed(1)} kg',
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

/// A row in the weight history: value + date, change from the previous entry,
/// and delete.
class WeightEntryRow extends StatelessWidget {
  const WeightEntryRow({
    super.key,
    required this.entry,
    required this.previousKg,
    required this.onDelete,
  });

  final WeightEntry entry;
  final double? previousKg;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = previousKg == null ? null : entry.kg - previousKg!;
    final time = entry.time;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.kg.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
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
            ),
          ),
          if (delta != null && delta != 0) WeightDeltaChip(delta: delta),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.weight.delete_confirm',
              onConfirm: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}
