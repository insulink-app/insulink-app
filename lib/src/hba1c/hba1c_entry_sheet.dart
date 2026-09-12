import 'package:flutter/material.dart';
import 'package:insulink/src/base/measurement_entry_sheet.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';
import 'package:provider/provider.dart';

/// Input sheet for an HbA1c reading (percent + timestamp). Pass [existing] to
/// correct a reading in place; omit it to note a new one, defaulting to now.
///
/// The accepted range is 3–20 %: below/above that the number is a typo (68 for
/// 6.8, or an mmol/mol figure pasted into the percent field), and a lab result
/// entered wrong would sit in the history for months.
Future<void> showHba1cEntrySheet(BuildContext context, {Hba1cEntry? existing}) {
  final state = context.read<Hba1cState>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MeasurementEntrySheet(
      titleKey: existing == null ? 'hba1c.add' : 'hba1c.edit',
      fieldLabelKey: 'hba1c._',
      timeLabelKey: 'hba1c.measured_at',
      unit: '%',
      initialValue: existing?.percent,
      initialTime: existing?.time,
      min: 3,
      max: 20,
      onSave: (percent, at) => existing == null
          ? state.add(percent, at: at)
          : state.edit(existing, percent: percent, at: at),
    ),
  );
}
