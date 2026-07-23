import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../localization/locale_text.dart';
import '../localization/locales.dart';
import 'inventory_item.dart';

/// A bottom sheet asking for a single whole number (stock, quantity). Returns
/// the entered value, or null if dismissed.
Future<int?> showNumberSheet(
  BuildContext context, {
  required String titleKey,
  int? initial,
}) {
  final controller = TextEditingController(text: initial?.toString() ?? '');
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _SheetBody(
      children: [
        LocaleText(titleKey, style: _titleStyle),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () =>
              Navigator.pop(sheetContext, int.tryParse(controller.text)),
          child: LocaleText('inventory.save'),
        ),
      ],
    ),
  );
}

/// A bottom sheet to add or edit a delivery — date and quantity together.
/// Returns the built [Delivery], or null if dismissed.
Future<Delivery?> showDeliverySheet(
  BuildContext context, {
  Delivery? existing,
}) {
  return showModalBottomSheet<Delivery>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DeliverySheet(existing: existing),
  );
}

const _titleStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.bold);

/// Sheet padding + keyboard inset, shared by the sheets above.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _DeliverySheet extends StatefulWidget {
  const _DeliverySheet({this.existing});

  final Delivery? existing;

  @override
  State<_DeliverySheet> createState() => _DeliverySheetState();
}

class _DeliverySheetState extends State<_DeliverySheet> {
  late DateTime _date =
      widget.existing?.date ?? DateTime.now().add(const Duration(days: 7));
  late final _quantity = TextEditingController(
      text: widget.existing?.quantity.toString() ?? '');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _date.isBefore(now) ? now : _date,
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _save() {
    final quantity = int.tryParse(_quantity.text);
    if (quantity == null || quantity <= 0) {
      return;
    }
    Navigator.pop(
      context,
      Delivery(atEpochMs: _date.millisecondsSinceEpoch, quantity: quantity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return _SheetBody(
      children: [
        LocaleText('inventory.delivery', style: _titleStyle),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(DateFormat.yMMMd(locale).format(_date)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _quantity,
          autofocus: widget.existing == null,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: Locales.string(context, 'inventory.quantity'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _save,
          child: LocaleText('inventory.save'),
        ),
      ],
    );
  }
}
