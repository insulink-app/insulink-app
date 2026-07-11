import 'package:flutter/material.dart';
import 'package:insulink/src/injection/injection_portion_sheet.dart';
import 'package:insulink/src/injection/injection_product_picker.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';

/// One chosen product with its portion in the product's unit; carbs scale from
/// the per-100 g value.
class _Item {
  final FoodProduct product;
  double grams;

  _Item(this.product, this.grams);

  double get carbs => product.carbs100g * grams / 100;

  MealEntry toEntry() => MealEntry(
    name: product.name.isEmpty ? product.barcode : product.name,
    unit: product.unit,
    amount: grams,
    carbs: carbs,
    protein: product.protein100g * grams / 100,
    servingSize: product.servingSize,
  );
}

/// "Products" carb source: pick products from the food database (searchable) and
/// set a portion each via the portion sheet; the picked entries are reported via
/// [onItemsChanged] so the sheet sums their carbs into the same bolus
/// calculation as the manual field AND can log them with the meal.
class InjectionProductsTab extends StatefulWidget {
  const InjectionProductsTab({super.key, required this.onItemsChanged});

  final void Function(List<MealEntry> items) onItemsChanged;

  @override
  State<InjectionProductsTab> createState() => _InjectionProductsTabState();
}

class _InjectionProductsTabState extends State<InjectionProductsTab> {
  final List<_Item> _items = [];

  double get _totalCarbs => _items.fold(0, (sum, item) => sum + item.carbs);

  void _notify() {
    setState(() {});
    widget.onItemsChanged(_items.map((item) => item.toEntry()).toList());
  }

  Future<void> _addProduct() async {
    final picked = await pickFoodProduct(context);
    if (picked == null || !mounted) {
      return;
    }
    final grams = await showPortionSheet(
      context,
      picked,
      picked.servingSize ?? 100,
    );
    if (grams == null || !mounted) {
      return;
    }
    _items.add(_Item(picked, grams));
    _notify();
  }

  Future<void> _editPortion(_Item item) async {
    final grams = await showPortionSheet(context, item.product, item.grams);
    if (grams == null || !mounted) {
      return;
    }
    item.grams = grams;
    _notify();
  }

  void _remove(_Item item) {
    _items.remove(item);
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items) _row(item),
        const SizedBox(height: 4),
        _addButton(),
        if (_items.isNotEmpty) _total(),
      ],
    );
  }

  /// Outlined "add" tile — a primary-bordered, transparent button so it reads as
  /// the add action without competing with the solid "Next" button below.
  Widget _addButton() {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: _addProduct,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: LocaleText('injection.products.add'),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _row(_Item item) {
    final scheme = Theme.of(context).colorScheme;
    final name = item.product.name.isEmpty
        ? item.product.barcode
        : item.product.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editPortion(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmt(item.grams)} ${item.product.unit} · '
                        '${item.carbs.toStringAsFixed(0)} g '
                        '${Locales.string(context, 'injection.products.carbs')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                  onPressed: () => _remove(item),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _total() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LocaleText(
            'injection.products.total',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
          Text(
            '${_totalCarbs.toStringAsFixed(0)} g',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
