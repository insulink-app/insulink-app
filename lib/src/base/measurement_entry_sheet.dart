import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Input sheet body for a dated decimal measurement (a weight, an HbA1c result):
/// one number field plus the instant it was measured, and a save button that
/// stays disabled until the number parses inside [min]..[max].
///
/// The caller owns persistence — [onSave] receives the parsed value and the
/// chosen timestamp — and owns the modal itself, so a feature can wrap the sheet
/// in whatever provider its state needs.
class MeasurementEntrySheet extends StatefulWidget {
  const MeasurementEntrySheet({
    super.key,
    required this.titleKey,
    required this.fieldLabelKey,
    required this.timeLabelKey,
    required this.unit,
    required this.onSave,
    this.initialValue,
    this.initialTime,
    this.decimals = 1,
    this.min = 0,
    this.max = double.infinity,
  });

  final String titleKey;
  final String fieldLabelKey;
  final String timeLabelKey;
  final String unit;

  /// Prefilled value + timestamp when editing; null/now when adding.
  final double? initialValue;
  final DateTime? initialTime;

  final int decimals;

  /// Accepted range, exclusive of [min]. A value outside it leaves the save
  /// button disabled — a typo like 68 instead of 6.8 must not become history.
  final double min;
  final double max;

  final void Function(double value, DateTime at) onSave;

  @override
  State<MeasurementEntrySheet> createState() => _MeasurementEntrySheetState();
}

class _MeasurementEntrySheetState extends State<MeasurementEntrySheet> {
  final _controller = TextEditingController();
  late DateTime _at;

  @override
  void initState() {
    super.initState();
    _at = widget.initialTime ?? DateTime.now();
    final initial = widget.initialValue;
    if (initial != null) {
      _controller.text = sportDecimal(initial, widget.decimals);
    }
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The typed number when it parses and lies inside the accepted range, else
  /// null (which disables saving). Accepts a comma as the decimal separator.
  double? get _value {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (parsed == null || parsed <= widget.min || parsed > widget.max) {
      return null;
    }
    return parsed;
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _save() {
    widget.onSave(_value!, _at);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return InkSheet(
      titleKey: widget.titleKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: Locales.string(context, widget.fieldLabelKey),
              suffixText: widget.unit,
            ),
          ),
          const SizedBox(height: 16),
          MeasurementTimeRow(
            at: _at,
            labelKey: widget.timeLabelKey,
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: value == null ? null : _save,
            child: LocaleText('alert.done'),
          ),
        ],
      ),
    );
  }
}

/// Tappable row showing the selected timestamp of the entry.
class MeasurementTimeRow extends StatelessWidget {
  const MeasurementTimeRow({
    super.key,
    required this.at,
    required this.labelKey,
    required this.onTap,
  });

  final DateTime at;
  final String labelKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: context.ink.ground,
      borderRadius: BorderRadius.circular(InkRadius.field),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.clock, size: 20, color: context.accent),
              const SizedBox(width: 12),
              LocaleText(
                labelKey,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                DateFormat('dd.MM.yyyy, HH:mm', 'de').format(at),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                PhosphorIconsBold.pencilSimple,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
