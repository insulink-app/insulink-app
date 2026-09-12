import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/locales.dart';
import 'inventory_item.dart';
import 'inventory_state.dart';
import 'inventory_stock_stepper.dart';

/// One inventory item: name, a stock bar (current vs base stock), a +/- stepper
/// to adjust it, the projected run-out, the surplus expected after the next
/// delivery, and a coloured warning line when it needs restocking. Tapping the
/// card opens [onEdit].
class InventoryItemCard extends StatelessWidget {
  const InventoryItemCard({
    super.key,
    required this.item,
    required this.onEdit,
  });

  final InventoryItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final status = item.status(now);
    final locale = Localizations.localeOf(context).toString();
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InventoryStockStepper(
                    stock: item.stock,
                    onChanged: (value) =>
                        context.read<InventoryState>().setStock(item.id, value),
                  ),
                ],
              ),
              if (item.baseStock > 0) ...[
                const SizedBox(height: 4),
                _stockBar(context, status, scheme),
                const SizedBox(height: 4),
                Text(
                  Locales.string(
                    context,
                    'inventory.stock_of',
                    params: ['${item.stock}', '${item.baseStock}'],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(_runOutText(context, now, locale)),
              if ((item.surplusBeforeNextDelivery(now) ?? -1) >= 0)
                Text(
                  Locales.string(
                    context,
                    'inventory.surplus',
                    params: ['${item.surplusBeforeNextDelivery(now)!.round()}'],
                  ),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              if (status != StockStatus.ok) ...[
                const SizedBox(height: 6),
                _warning(context, status, scheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stockBar(
    BuildContext context,
    StockStatus status,
    ColorScheme scheme,
  ) {
    final color = switch (status) {
      StockStatus.shortage => scheme.error,
      StockStatus.low => Colors.orange,
      StockStatus.ok => scheme.primary,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: item.stockFraction,
        minHeight: 8,
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }

  String _runOutText(BuildContext context, DateTime now, String locale) {
    final runOut = item.runOutDate(now);
    if (runOut == null) {
      return Locales.string(context, 'inventory.runs_out_never');
    }
    final days = runOut.difference(now).inDays;
    return Locales.string(
      context,
      'inventory.runs_out',
      params: [DateFormat.yMMMd(locale).format(runOut), '$days'],
    );
  }

  Widget _warning(
    BuildContext context,
    StockStatus status,
    ColorScheme scheme,
  ) {
    final shortage = status == StockStatus.shortage;
    final color = shortage ? scheme.error : Colors.orange;
    return Text(
      Locales.string(
        context,
        shortage ? 'inventory.shortage_warning' : 'inventory.low_warning',
      ),
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
