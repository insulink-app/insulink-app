import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

import '../base/confirm_delete.dart';
import '../base/labeled_field.dart';
import '../localization/locale_text.dart';
import '../localization/locales.dart';
import '../theme/status_colors.dart';
import 'inventory_delivery_list.dart';
import 'inventory_dropdown.dart';
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
  late final _stock = TextEditingController(
    text: '${widget.existing?.stock ?? ''}',
  );
  late final _baseStock = TextEditingController(
    text: '${widget.existing?.baseStock ?? ''}',
  );
  late final _daysPerUnit = TextEditingController(
    text: '${widget.existing?.daysPerUnit ?? ''}',
  );
  late final List<Delivery> _deliveries = [...?widget.existing?.deliveries];
  late ItemType _type = widget.existing?.type ?? ItemType.other;
  late SensorBrand _brand = widget.existing?.sensorBrand ?? SensorBrand.other;
  // Defaults to the pump the app drives, since that is the only one it can
  // decrement automatically.
  late PumpBrand _pumpBrand =
      widget.existing?.pumpBrand ?? PumpBrand.omnipodDash;

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
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      stock: stock,
      baseStock: int.tryParse(_baseStock.text) ?? stock,
      daysPerUnit: _resolveDaysPerUnit(),
      anchorMs: DateTime.now().millisecondsSinceEpoch,
      type: _type,
      sensorBrand: _type == ItemType.sensor ? _brand : null,
      pumpBrand: _type == ItemType.pump ? _pumpBrand : null,
      deliveries: _deliveries,
    );
    context.read<InventoryState>().addOrUpdate(item);
    Navigator.pop(context);
  }

  /// Whether the user has to say how long a unit lasts, because the chosen
  /// hardware has no known figure.
  bool get _needsManualDuration => switch (_type) {
    ItemType.sensor => _brand.typicalDaysPerUnit == null,
    ItemType.pump => _pumpBrand.typicalDaysPerUnit == null,
    ItemType.other => true,
  };

  /// How long a unit lasts: the known figure for known hardware, otherwise what
  /// the user typed. Zero means "do not forecast".
  double _resolveDaysPerUnit() {
    final known = switch (_type) {
      ItemType.sensor => _brand.typicalDaysPerUnit,
      ItemType.pump => _pumpBrand.typicalDaysPerUnit,
      ItemType.other => null,
    };
    return known ??
        double.tryParse(_daysPerUnit.text.replaceAll(',', '.')) ??
        0;
  }

  /// Animate the days field in/out. A null child collapses it away.
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
              padding: const EdgeInsets.only(top: 14),
              child: child,
            ),
    );
  }

  /// A labelled text field; [digits] limits it to whole numbers.
  Widget _field(
    String labelKey,
    TextEditingController controller, {
    TextInputType? keyboard,
    bool digits = false,
  }) {
    return LabeledField(
      labelKey: labelKey,
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: digits
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
      ),
    );
  }

  /// Two fields side by side; a missing [right] lets [left] take the row.
  Widget _pair(Widget left, Widget? right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Expanded(child: left),
        if (right != null) Expanded(child: right),
      ],
    );
  }

  /// The brand picker for a sensor or a pump; none for any other item.
  Widget? _brandDropdown() {
    return switch (_type) {
      ItemType.sensor => InventoryDropdown<SensorBrand>(
        labelKey: 'inventory.brand',
        selected: _brand,
        values: SensorBrand.values,
        labelKeyOf: (brand) => 'inventory.brand_${brand.wireKey}',
        onChanged: (brand) => setState(() => _brand = brand),
      ),
      ItemType.pump => InventoryDropdown<PumpBrand>(
        labelKey: 'inventory.brand',
        selected: _pumpBrand,
        values: PumpBrand.values,
        labelKeyOf: (brand) => 'inventory.pump_brand_${brand.wireKey}',
        onChanged: (brand) => setState(() => _pumpBrand = brand),
      ),
      ItemType.other => null,
    };
  }

  /// Known hardware carries its own run time; everything else, an "other"
  /// item or a brand the app has no figure for, takes the number typed here.
  Widget? _daysField() {
    if (!_needsManualDuration) {
      return null;
    }
    return _field(
      'inventory.days_per_unit',
      _daysPerUnit,
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
  }

  void _confirmDelete() {
    confirmDelete(
      context,
      messageKey: 'inventory.delete_confirm',
      onConfirm: () {
        context.read<InventoryState>().remove(widget.existing!.id);
        Navigator.pop(context);
      },
    );
  }

  PreferredSizeWidget _appBar() {
    final editing = widget.existing != null;
    return AppBar(
      surfaceTintColor: Colors.transparent,
      title: LocaleText(
        editing ? 'inventory.edit_title' : 'inventory.add_title',
      ),
      actions: [
        if (editing)
          IconButton(
            icon: Icon(PhosphorIconsBold.trash, color: context.danger),
            tooltip: Locales.string(context, 'inventory.delete'),
            onPressed: _confirmDelete,
          ),
      ],
    );
  }

  /// "Speichern" pinned under the form, above the keyboard and the system bar.
  Widget _saveButton() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        8,
        InkSpace.panelMargin,
        16,
      ),
      child: FilledButton.icon(
        icon: const Icon(PhosphorIconsBold.check),
        label: LocaleText('inventory.save'),
        onPressed: _save,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      bottomNavigationBar: _saveButton(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          InkSpace.panelMargin,
          18,
          InkSpace.panelMargin,
          24,
        ),
        children: [
          _field('inventory.name', _name),
          const SizedBox(height: 14),
          _pair(
            _field(
              'inventory.stock',
              _stock,
              keyboard: TextInputType.number,
              digits: true,
            ),
            _field(
              'inventory.base_stock',
              _baseStock,
              keyboard: TextInputType.number,
              digits: true,
            ),
          ),
          const SizedBox(height: 14),
          _pair(
            InventoryDropdown<ItemType>(
              labelKey: 'inventory.type',
              selected: _type,
              values: ItemType.values,
              labelKeyOf: (type) => 'inventory.type_${type.wireKey}',
              onChanged: (type) => setState(() => _type = type),
            ),
            _brandDropdown(),
          ),
          _reveal('days', _daysField()),
          const SizedBox(height: 16),
          InventoryDeliveryList(
            deliveries: _deliveries,
            onAdd: _editDelivery,
            onEdit: _editDelivery,
            onRemove: (delivery) =>
                setState(() => _deliveries.remove(delivery)),
          ),
        ],
      ),
    );
  }
}
