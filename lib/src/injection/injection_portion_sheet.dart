import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Asks for a portion and previews the resulting carbs live. When the product
/// declares a serving size the input is a **number of servings** (the natural
/// intuition, e.g. "2 biscuits"); otherwise it falls back to an amount in the
/// product's unit (g/ml). Always returns the amount in grams/ml, so callers keep
/// the same carb math. Returns null when dismissed. Used when adding a product
/// and when editing an already-picked one.
Future<double?> showPortionSheet(
  BuildContext context,
  FoodProduct product,
  double initialGrams,
) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PortionSheet(product: product, initialGrams: initialGrams),
  );
}

class _PortionSheet extends StatefulWidget {
  const _PortionSheet({required this.product, required this.initialGrams});

  final FoodProduct product;
  final double initialGrams;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  late final double? _serving = (widget.product.servingSize ?? 0) > 0
      ? widget.product.servingSize
      : null;

  late final TextEditingController _input = TextEditingController(
    text: _fmt(
      _serving == null ? widget.initialGrams : widget.initialGrams / _serving,
    ),
  );

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  double get _count => double.tryParse(_input.text.replaceAll(',', '.')) ?? 0;

  /// One tap on the +/- stepper: a whole serving, or a 10 g/ml step when the
  /// product has no serving size.
  double get _step => _serving == null ? 10 : 1;

  void _bump(double delta) {
    final next = (_count + delta).clamp(0.0, double.infinity);
    _input.text = _fmt(next);
  }

  /// The amount in grams/ml — [_count] servings times the serving size, or the
  /// raw amount when there is no serving.
  double get _grams => _serving == null ? _count : _count * _serving;

  double get _carbs => widget.product.carbs100g * _grams / 100;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: 24 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          Text(
            widget.product.name.isEmpty
                ? widget.product.barcode
                : widget.product.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleIconButton(
                icon: PhosphorIconsBold.minus,
                accent: scheme.primary,
                onTap: () => _bump(-_step),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _input,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: Locales.string(
                      context,
                      _serving == null
                          ? 'injection.products.amount'
                          : 'injection.products.servings',
                    ),
                    suffixText: _serving == null ? widget.product.unit : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              CircleIconButton(
                icon: PhosphorIconsBold.plus,
                accent: scheme.primary,
                onTap: () => _bump(_step),
              ),
            ],
          ),
          if (_serving != null) ...[
            const SizedBox(height: 8),
            Text(
              _servingHint(),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _carbsRow(scheme),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _grams <= 0
                ? null
                : () => Navigator.of(context).pop(_grams),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: LocaleText('injection.products.confirm'),
          ),
        ],
      ),
    );
  }

  Widget _carbsRow(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LocaleText(
          'injection.products.carbs',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
        ),
        Text(
          '${_carbs.toStringAsFixed(0)} g',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }

  /// The serving description the product reported (e.g. "1 biscuit (12.5 g)"),
  /// with the current total amount in the product's unit appended.
  String _servingHint() {
    final label = widget.product.servingLabel.isNotEmpty
        ? widget.product.servingLabel
        : '1 ${Locales.string(context, 'injection.products.serving_one')}'
              ' = ${_fmt(_serving!)} ${widget.product.unit}';
    return '$label · ≈ ${_grams.toStringAsFixed(0)} ${widget.product.unit}';
  }

  String _fmt(double value) => value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
