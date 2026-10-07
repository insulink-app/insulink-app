import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/base/labeled_field.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:provider/provider.dart';

/// Full editor for a product — used to add one manually, to complete the fields
/// a barcode scan left blank, and to edit an existing product. Saves into
/// [FoodState] (keyed by barcode, so editing replaces).
///
/// Returns the SAVED product, or null when the sheet was dismissed without
/// saving. The bolus product picker needs it: a product created there is the one
/// the user is about to dose for, so it goes straight on to the portion instead
/// of having to be found again in the list.
Future<FoodProduct?> showFoodEditor(
  BuildContext context, {
  FoodProduct? product,
}) {
  return showInkSheet<FoodProduct>(
    context: context,
    builder: (_) => _FoodEditorSheet(product: product ?? FoodProduct.blank()),
  );
}

class _FoodEditorSheet extends StatefulWidget {
  const _FoodEditorSheet({required this.product});

  final FoodProduct product;

  @override
  State<_FoodEditorSheet> createState() => _FoodEditorSheetState();
}

class _FoodEditorSheetState extends State<_FoodEditorSheet> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _brand = TextEditingController(text: widget.product.brand);
  late final _serving = TextEditingController(
    text: _numText(widget.product.servingSize),
  );
  late final _servingLabel = TextEditingController(
    text: widget.product.servingLabel,
  );
  late final _carbs = TextEditingController(
    text: _numText(widget.product.carbs100g),
  );
  late final _fat = TextEditingController(
    text: _numText(widget.product.fat100g),
  );
  late final _protein = TextEditingController(
    text: _numText(widget.product.protein100g),
  );
  late final _kcal = TextEditingController(
    text: _numText(widget.product.kcal100g),
  );
  late String _unit = widget.product.unit;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _brand,
      _serving,
      _servingLabel,
      _carbs,
      _fat,
      _protein,
      _kcal,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  FoodProduct _build() {
    final barcode = widget.product.barcode.isEmpty
        ? 'manual-${DateTime.now().millisecondsSinceEpoch}'
        : widget.product.barcode;
    return FoodProduct(
      barcode: barcode,
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      unit: _unit,
      servingSize: _num(_serving.text),
      servingLabel: _servingLabel.text.trim(),
      carbs100g: _num(_carbs.text) ?? 0,
      fat100g: _num(_fat.text) ?? 0,
      protein100g: _num(_protein.text) ?? 0,
      kcal100g: _num(_kcal.text) ?? 0,
    );
  }

  void _save() {
    final saved = _build();
    context.read<FoodState>().addProduct(saved);
    Navigator.pop(context, saved);
  }

  /// Name, brand, serving size with the g/ml switch beside it, serving
  /// description, then the nutrients per 100 g or ml as a 2 × 2 grid and
  /// "Fertig" (`docs/redesign/screens/34-produkt-bearbeiten.png`).
  @override
  Widget build(BuildContext context) {
    return InkSheet(
      titleKey: widget.product.name.isEmpty
          ? 'nutrition.food.add_title'
          : 'nutrition.food.edit_title',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            _field('nutrition.food.name', _name),
            _field('nutrition.food.brand', _brand),
            _servingRow(),
            _field('nutrition.food.serving_label', _servingLabel),
            _nutrientsHeader(),
            _pair(
              _field(
                'nutrition.food.carbs_long',
                _carbs,
                number: true,
                suffix: 'g',
              ),
              _field(
                'nutrition.food.energy',
                _kcal,
                number: true,
                suffix: 'kcal',
              ),
            ),
            _pair(
              _field('nutrition.food.fat', _fat, number: true, suffix: 'g'),
              _field(
                'nutrition.food.protein',
                _protein,
                number: true,
                suffix: 'g',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _save, child: LocaleText('alert.done')),
          ],
        ),
      ),
    );
  }

  /// A labelled field filled with the page colour, the unit at its end.
  Widget _field(
    String labelKey,
    TextEditingController controller, {
    bool number = false,
    String? suffix,
  }) {
    return LabeledField(
      labelKey: labelKey,
      fill: context.ink.ground,
      child: TextField(
        controller: controller,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : null,
        decoration: InputDecoration(suffixText: suffix),
      ),
    );
  }

  Widget _pair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Expanded(child: left),
        Expanded(child: right),
      ],
    );
  }

  /// The serving size with the small g/ml switch to its right, in place of
  /// the full-width unit selector.
  Widget _servingRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 10,
      children: [
        Expanded(
          child: _field(
            'nutrition.food.serving_size',
            _serving,
            number: true,
            suffix: _unit,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            width: 112,
            child: SegmentedToggle<String>(
              selected: _unit,
              onChanged: (unit) => setState(() => _unit = unit),
              options: const [
                (value: 'g', label: 'g'),
                (value: 'ml', label: 'ml'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// "Nährwerte" with "pro 100 ml" on the right.
  Widget _nutrientsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: LocaleText(
              'nutrition.food.nutrients',
              style: InkText.section,
            ),
          ),
          LocaleText(
            'nutrition.food.per_100',
            params: [_unit],
            style: InkText.label.copyWith(color: context.ink.muted),
          ),
        ],
      ),
    );
  }

  String _numText(double? value) {
    if (value == null || value == 0) {
      return '';
    }
    return value.toString().replaceAll('.', ',');
  }

  double? _num(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));
}
