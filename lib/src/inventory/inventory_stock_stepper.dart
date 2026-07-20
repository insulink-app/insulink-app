import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'inventory_sheets.dart';

/// Compact stock control: minus / current count / plus, with the count tappable
/// to type an exact value. Reports the NEW absolute stock via [onChanged].
class InventoryStockStepper extends StatelessWidget {
  const InventoryStockStepper({
    super.key,
    required this.stock,
    required this.onChanged,
  });

  final int stock;
  final ValueChanged<int> onChanged;

  Future<void> _typeValue(BuildContext context) async {
    final value = await showNumberSheet(
      context,
      titleKey: 'inventory.set_stock',
      initial: stock,
    );
    if (value != null) {
      onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.minus, size: 18),
          onPressed: stock > 0 ? () => onChanged(stock - 1) : null,
        ),
        GestureDetector(
          onTap: () => _typeValue(context),
          child: SizedBox(
            width: 34,
            child: Text(
              '$stock',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(PhosphorIconsBold.plus, size: 18),
          onPressed: () => onChanged(stock + 1),
        ),
      ],
    );
  }
}
