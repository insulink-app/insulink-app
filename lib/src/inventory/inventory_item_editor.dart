import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

import '../base/confirm_delete.dart';
import '../localization/locale_text.dart';
import '../localization/locales.dart';
import 'inventory_item.dart';
import 'inventory_sheets.dart';
import 'inventory_state.dart';

/// Add/edit form for one [InventoryItem]. Deliveries are added or edited via a
/// bottom sheet (date + quantity together); tapping a row edits it.
class InventoryItemEditor extends StatefulWidget {
  const InventoryItemEditor({super.key, this.existing});

  final InventoryItem? existing;

  @override
  State<InventoryItemEditor> createState() => _InventoryItemEditorState();
}

class _InventoryItemEditorState extends State<InventoryItemEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _stock =
      TextEditingController(text: '${widget.existing?.stock ?? ''}');
  late final _baseStock =
      TextEditingController(text: '${widget.existing?.baseStock ?? ''}');
  late final _daysPerUnit =
      TextEditingController(text: '${widget.existing?.daysPerUnit ?? ''}');
  late final List<Delivery> _deliveries = [...?widget.existing?.deliveries];
  late ItemType _type = widget.existing?.type ?? ItemType.other;
  late SensorBrand _brand =
      widget.existing?.sensorBrand ?? SensorBrand.other;

  @override
  void dispose() {
    _name.dispose();
    _stock.dispose();
    _baseStock.dispose();
    _daysPerUnit.dispose();
    super.dispose();
  }

  /// Add a new delivery, or (when [existing] is passed) edit that one in place,
  /// via a bottom sheet that takes date + quantity together.
  Future<void> _editDelivery([Delivery? existing]) async {
    final updated = await showDeliverySheet(context, existing: existing);
    if (updated == null) {
      return;
    }
    setState(() {
      final index = existing == null ? -1 : _deliveries.indexOf(existing);
      if (index >= 0) {
        _deliveries[index] = updated;
      } else {
        _deliveries.add(updated);
      }
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    final stock = int.tryParse(_stock.text) ?? 0;
    final item = InventoryItem(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      stock: stock,
      baseStock: int.tryParse(_baseStock.text) ?? stock,
      daysPerUnit: _resolveDaysPerUnit(),
      anchorMs: DateTime.now().millisecondsSinceEpoch,
      type: _type,
      sensorBrand: _type == ItemType.sensor ? _brand : null,
      deliveries: _deliveries,
    );
    context.read<InventoryState>().addOrUpdate(item);
    Navigator.pop(context);
  }

  /// How long a unit lasts. Sensors and pumps have known run times; only an
  /// "other" item takes the value the user typed.
  double _resolveDaysPerUnit() {
    switch (_type) {
      case ItemType.sensor:
        return _brand.typicalDaysPerUnit ?? 0;
      case ItemType.pump:
        // ponytail: Omnipod DASH pod (~72 h) — the only supported pump; keyed
        // off a PumpBrand once the app models pump brands like sensor brands.
        return 3;
      case ItemType.other:
        return double.tryParse(_daysPerUnit.text.replaceAll(',', '.')) ?? 0;
    }
  }

  /// Animate a conditional field in/out (the brand + days fields). A null child
  /// collapses it away.
  Widget _reveal(String id, Widget? child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (revealed, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: revealed),
      ),
      child: child == null
          ? SizedBox(key: ValueKey('$id-none'), width: double.infinity)
          : Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.only(top: 16),
              child: child,
            ),
    );
  }

  /// A soft, rounded, filled dropdown that fills the row width like the text
  /// fields above it. Uses M3 [DropdownMenu] instead of [DropdownButtonFormField]
  /// because the latter's popup renders wider than its field and drifts to the
  /// screen edges; [DropdownMenu]'s menu tracks the field width, and
  /// [DropdownMenu.expandedInsets] `zero` makes the field fill the row exactly.
  Widget _dropdown<T>(
    String labelKey,
    T selected,
    List<T> values,
    String Function(T) labelKeyOf,
    ValueChanged<T> onChanged,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownMenu<T>(
      key: ValueKey(selected),
      initialSelection: selected,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      label: LocaleText(labelKey),
      trailingIcon: const Icon(PhosphorIconsBold.caretDown, size: 16),
      selectedTrailingIcon: const Icon(PhosphorIconsBold.caretUp, size: 16),
      onSelected: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      menuStyle: MenuStyle(
        backgroundColor:
            WidgetStatePropertyAll(scheme.surfaceContainerHighest),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      dropdownMenuEntries: [
        for (final value in values)
          DropdownMenuEntry(
            value: value,
            label: Locales.string(context, labelKeyOf(value)),
          ),
      ],
    );
  }

  /// One planned delivery as a soft rounded row: truck glyph, date, a tinted
  /// "+N" quantity pill and a remove button. Tapping the row edits it.
  Widget _deliveryTile(Delivery delivery, String locale) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editDelivery(delivery),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsBold.truck, size: 18, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(DateFormat.yMMMd(locale).format(delivery.date))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+${delivery.quantity}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 16),
                  visualDensity: VisualDensity.compact,
                  // ponytail: no confirm — an uncommitted form edit, only "save"
                  // persists it, so a prompt per delivery row would just nag.
                  onPressed: () => setState(() => _deliveries.remove(delivery)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('inventory.label'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash),
              onPressed: () => confirmDelete(
                context,
                messageKey: 'inventory.delete_confirm',
                onConfirm: () {
                  context.read<InventoryState>().remove(widget.existing!.id);
                  Navigator.pop(context);
                },
              ),
            ),
          IconButton(icon: const Icon(PhosphorIconsBold.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
                labelText: Locales.string(context, 'inventory.name')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _stock,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
                labelText: Locales.string(context, 'inventory.stock')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseStock,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
                labelText: Locales.string(context, 'inventory.base_stock')),
          ),
          const SizedBox(height: 16),
          _dropdown<ItemType>(
            'inventory.type',
            _type,
            ItemType.values,
            (type) => 'inventory.type_${type.wireKey}',
            (type) => setState(() => _type = type),
          ),
          _reveal(
            'brand',
            _type == ItemType.sensor
                ? _dropdown<SensorBrand>(
                    'inventory.brand',
                    _brand,
                    SensorBrand.values,
                    (brand) => 'inventory.brand_${brand.wireKey}',
                    (brand) => setState(() => _brand = brand),
                  )
                : null,
          ),
          // Sensors and pumps have known run times (derived on save); only for
          // "other" does the user enter how long a unit lasts.
          _reveal(
            'days',
            _type == ItemType.other
                ? TextField(
                    controller: _daysPerUnit,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText:
                            Locales.string(context, 'inventory.days_per_unit')),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LocaleText('inventory.deliveries',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(PhosphorIconsBold.plus),
                onPressed: () => _editDelivery(),
              ),
            ],
          ),
          if (_deliveries.isEmpty)
            LocaleText(
              'inventory.no_deliveries',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          for (final delivery in _deliveries)
            _deliveryTile(delivery, locale),
        ],
      ),
    );
  }
}
