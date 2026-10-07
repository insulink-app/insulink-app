import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../base/stepper_pill.dart';
import '../localization/locales.dart';
import '../theme/insulink_theme.dart';
import '../theme/status_colors.dart';
import 'inventory_item.dart';
import 'inventory_sheets.dart';
import 'inventory_state.dart';
import 'inventory_stock_bar.dart';

/// One inventory item as a card: name with the stock stepper, the stock bar
/// (current vs base stock) with "x von y Stück" and the days left, the
/// projected run-out in bold, the surplus expected before the next delivery,
/// and a coloured warning line when it needs restocking. Tapping the card
/// opens [onEdit].
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
    final colors = context.ink;
    final now = DateTime.now();
    final status = item.status(now);
    final surplus = item.surplusBeforeNextDelivery(now);
    return Material(
      color: colors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InkRadius.tile),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(context),
              InventoryStockBar(item: item, status: status, now: now),
              const SizedBox(height: 10),
              Text(
                _runOutText(context, now),
                style: InkText.label.copyWith(fontWeight: FontWeight.w700),
              ),
              if ((surplus ?? -1) >= 0)
                _muted(
                  Locales.string(
                    context,
                    'inventory.surplus',
                    params: ['${surplus!.round()}'],
                  ),
                  colors,
                ),
              if (status != StockStatus.ok) _warning(context, status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head(BuildContext context) {
    final stock = item.stock;
    void setStock(int value) =>
        context.read<InventoryState>().setStock(item.id, value);
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: InkText.rowTitle.copyWith(fontSize: 17),
          ),
        ),
        StepperPill(
          value: '$stock',
          onMinus: stock > 0 ? () => setStock(stock - 1) : null,
          onPlus: () => setStock(stock + 1),
          onValueTap: () => _typeStock(context, setStock),
          minusLabelKey: 'inventory.decrease',
          plusLabelKey: 'inventory.increase',
        ),
      ],
    );
  }

  /// Opens the number sheet to set the stock to an exact count.
  Future<void> _typeStock(
    BuildContext context,
    ValueChanged<int> setStock,
  ) async {
    final value = await showNumberSheet(
      context,
      titleKey: 'inventory.set_stock',
      initial: item.stock,
    );
    if (value != null) {
      setStock(value);
    }
  }

  String _runOutText(BuildContext context, DateTime now) {
    final runOut = item.runOutDate(now);
    if (runOut == null) {
      return Locales.string(context, 'inventory.runs_out_never');
    }
    final locale = Localizations.localeOf(context).toString();
    return Locales.string(
      context,
      'inventory.runs_out',
      params: [DateFormat.yMMMd(locale).format(runOut)],
    );
  }

  Widget _muted(String text, InsulinkColors colors) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(text, style: InkText.caption.copyWith(color: colors.muted)),
  );

  Widget _warning(BuildContext context, StockStatus status) {
    final shortage = status == StockStatus.shortage;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        Locales.string(
          context,
          shortage ? 'inventory.shortage_warning' : 'inventory.low_warning',
        ),
        style: InkText.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: shortage ? context.danger : context.warning,
        ),
      ),
    );
  }
}
