import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:provider/provider.dart';

/// Full editor for a product — used to add one manually, to complete the fields
/// a barcode scan left blank, and to edit an existing product. Saves into
/// [FoodState] (keyed by barcode, so editing replaces).
Future<void> showFoodEditor(BuildContext context, {FoodProduct? product}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
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
    context.read<FoodState>().addProduct(_build());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GrabHandle(),
            const SizedBox(height: 16),
            _field('nutrition.food.name', _name),
            _field('nutrition.food.brand', _brand),
            _unitSelector(theme),
            _field(
              'nutrition.food.serving_size',
              _serving,
              number: true,
              suffix: _unit,
            ),
            _field('nutrition.food.serving_label', _servingLabel),
            const SizedBox(height: 16),
            LocaleText(
              'nutrition.food.per_100',
              params: [_unit],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            _field('nutrition.food.carbs', _carbs, number: true, suffix: 'g'),
            _field('nutrition.food.fat', _fat, number: true, suffix: 'g'),
            _field(
              'nutrition.food.protein',
              _protein,
              number: true,
              suffix: 'g',
            ),
            _field('nutrition.food.kcal', _kcal, number: true, suffix: 'kcal'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const LocaleText(
                'alert.done',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String labelKey,
    TextEditingController controller, {
    bool number = false,
    String? suffix,
  }) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        cursorColor: accent,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : null,
        decoration: InputDecoration(
          labelText: Locales.string(context, labelKey),
          // No local floatingLabelStyle — inherit the theme's neutral-grey label
          // instead of tinting it primary.
          suffixText: suffix,
          isDense: true,
          filled: true,
          fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _unitSelector(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          foregroundColor: theme.colorScheme.onSurface,
          selectedBackgroundColor: accent,
          selectedForegroundColor: theme.colorScheme.onPrimary,
          side: BorderSide(color: theme.dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        segments: const [
          ButtonSegment(value: 'g', label: Text('g')),
          ButtonSegment(value: 'ml', label: Text('ml')),
        ],
        selected: {_unit},
        onSelectionChanged: (selection) =>
            setState(() => _unit = selection.first),
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
