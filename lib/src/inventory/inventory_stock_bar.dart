import 'package:flutter/material.dart';

import '../base/track_bar.dart';
import '../localization/locales.dart';
import '../theme/insulink_theme.dart';
import '../theme/status_colors.dart';
import 'inventory_item.dart';

/// The stock of an inventory card: a bar of current vs base stock, coloured by
/// how urgent a restock is, over "x von y Stück" left and "noch n Tage" right.
/// Without a base stock only the days are left; without a run-out date only
/// the bar and the count.
class InventoryStockBar extends StatelessWidget {
  const InventoryStockBar({
    super.key,
    required this.item,
    required this.status,
    required this.now,
  });

  final InventoryItem item;
  final StockStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final runOut = item.runOutDate(now);
    final style = InkText.caption.copyWith(color: colors.muted);
    final hasBase = item.baseStock > 0;
    if (!hasBase && runOut == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasBase) ...[
          const SizedBox(height: 14),
          TrackBar(
            startFraction: 0,
            endFraction: item.stockFraction,
            color: _barColor(context, status),
            height: 6,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: hasBase
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: [
            if (hasBase)
              Text(
                Locales.string(
                  context,
                  'inventory.stock_of',
                  params: ['${item.stock}', '${item.baseStock}'],
                ),
                style: style,
              ),
            if (runOut != null)
              Text(
                Locales.string(
                  context,
                  'inventory.days_left',
                  params: ['${runOut.difference(now).inDays}'],
                ),
                style: style,
              ),
          ],
        ),
      ],
    );
  }

  Color _barColor(BuildContext context, StockStatus status) => switch (status) {
    StockStatus.shortage => context.danger,
    StockStatus.low => context.warning,
    StockStatus.ok => context.ink.accent,
  };
}
