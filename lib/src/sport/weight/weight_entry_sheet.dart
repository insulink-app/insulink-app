import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/base/measurement_entry_sheet.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:provider/provider.dart';

/// Input sheet for a weight entry (kg + timestamp). Pass [existing] to edit an
/// entry in place; omit it to add a new one defaulting to now.
Future<void> showWeightEntrySheet(
  BuildContext context, {
  WeightEntry? existing,
}) {
  final state = context.read<SportState>();
  return showInkSheet(
    context: context,
    builder: (_) => MeasurementEntrySheet(
      titleKey: existing == null ? 'sport.weight.add' : 'sport.weight.edit',
      fieldLabelKey: 'sport.weight',
      timeLabelKey: 'sport.weight.time',
      unit: 'kg',
      initialValue: existing?.kg,
      initialTime: existing?.time,
      onSave: (kg, at) => existing == null
          ? state.addWeight(kg, at: at)
          : state.editWeight(existing, kg: kg, at: at),
    ),
  );
}
