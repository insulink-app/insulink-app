import 'package:flutter/material.dart';
import 'package:insulink/src/base/measurement_row.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// A row in the weight history: value + date, change from the previous entry,
/// and delete. A thin adapter over the shared [MeasurementRow].
class WeightEntryRow extends StatelessWidget {
  const WeightEntryRow({
    super.key,
    required this.entry,
    required this.previousKg,
    required this.onDelete,
    required this.onEdit,
  });

  final WeightEntry entry;
  final double? previousKg;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return MeasurementRow(
      value: entry.kg,
      time: entry.time,
      unit: 'kg',
      previous: previousKg,
      deleteConfirmKey: 'sport.weight.delete_confirm',
      onDelete: onDelete,
      onEdit: onEdit,
    );
  }
}
