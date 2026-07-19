import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_state.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Input sheet for a weight entry (kg + timestamp). Pass [existing] to edit an
/// entry in place; omit it to add a new one defaulting to now.
Future<void> showWeightEntrySheet(BuildContext context, {WeightEntry? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<SportState>(),
      child: _WeightEntrySheet(existing: existing),
    ),
  );
}

class _WeightEntrySheet extends StatefulWidget {
  const _WeightEntrySheet({this.existing});

  final WeightEntry? existing;

  @override
  State<_WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends State<_WeightEntrySheet> {
  final _controller = TextEditingController();
  late DateTime _at;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _at = existing?.time ?? DateTime.now();
    if (existing != null) {
      _controller.text = sportDecimal(existing.kg, 1);
    }
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _kg {
    final value = double.tryParse(_controller.text.replaceAll(',', '.'));
    return (value != null && value > 0) ? value : null;
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
    final existing = widget.existing;
    final state = context.read<SportState>();
    if (existing == null) {
      state.addWeight(_kg!, at: _at);
    } else {
      state.editWeight(existing, kg: _kg!, at: _at);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kg = _kg;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          LocaleText(
            widget.existing == null ? 'sport.weight.add' : 'sport.weight.edit',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: Locales.string(context, 'sport.weight'),
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 16),
          _TimeRow(at: _at, onTap: _pickDateTime),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: kg == null ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: LocaleText('alert.done'),
          ),
        ],
      ),
    );
  }
}

/// Tappable row showing the selected timestamp of the weight entry.
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.at, required this.onTap});

  final DateTime at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
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
                'sport.weight.time',
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
