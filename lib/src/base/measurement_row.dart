import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/change_chip.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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
    return ChangeChip(
      label: '${sportDecimal(delta.abs(), decimals)} $unit',
      up: up,
      bad: up == risingIsBad,
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
    this.framed = true,
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

  /// Whether the row brings its own panel (see [build]).
  final bool framed;

  /// A bare row inside an [InkPanel.list]; [framed] gives a row standing on
  /// its own a panel of its own.
  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : value - previous!;
    final row = InkWell(
      onTap: onEdit,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(
            spacing: 6,
            children: [
              Expanded(child: _valueAndDate(context)),
              if (delta != null && delta != 0)
                MeasurementDeltaChip(
                  delta: delta,
                  unit: unit,
                  decimals: decimals,
                ),
              IconButton(
                tooltip: Locales.string(context, 'alert.delete'),
                icon: Icon(
                  PhosphorIconsBold.trash,
                  size: 20,
                  color: context.ink.muted,
                ),
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
    return framed ? InkPanel.list(rows: [row]) : row;
  }

  Widget _valueAndDate(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Text(
          '${sportDecimal(value, decimals)} $unit',
          style: InkText.rowTitle.copyWith(fontSize: 17),
        ),
        Text(
          RelativeDay(time).label(context),
          style: InkText.label.copyWith(color: context.ink.muted),
        ),
      ],
    );
  }
}
