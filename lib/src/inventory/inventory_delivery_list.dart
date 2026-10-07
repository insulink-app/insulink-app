import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../base/ink_panel.dart';
import '../base/list_row.dart';
import '../base/section_header.dart';
import '../localization/locale_text.dart';
import '../localization/locales.dart';
import '../theme/insulink_theme.dart';
import 'inventory_item.dart';

/// The planned deliveries of the item editor: a section title with "+", then
/// one row per delivery in a panel (truck disc, date, "+N" pill, remove).
/// Tapping a row edits it.
class InventoryDeliveryList extends StatelessWidget {
  const InventoryDeliveryList({
    super.key,
    required this.deliveries,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<Delivery> deliveries;
  final VoidCallback onAdd;
  final ValueChanged<Delivery> onEdit;
  final ValueChanged<Delivery> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SectionHeader(
            titleKey: 'inventory.deliveries',
            actions: [
              IconButton(
                icon: const Icon(PhosphorIconsBold.plus),
                tooltip: Locales.string(context, 'inventory.add_delivery'),
                onPressed: onAdd,
              ),
            ],
          ),
        ),
        if (deliveries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LocaleText(
              'inventory.no_deliveries',
              style: InkText.label.copyWith(color: context.ink.muted),
            ),
          )
        else
          InkPanel.list(
            rows: [for (final delivery in deliveries) _row(context, delivery)],
          ),
      ],
    );
  }

  /// ponytail: removing asks no confirmation. It is an uncommitted form edit
  /// that only "save" persists, so a prompt per delivery row would just nag.
  Widget _row(BuildContext context, Delivery delivery) {
    final locale = Localizations.localeOf(context).toString();
    return ListRow(
      icon: PhosphorIconsBold.truck,
      title: DateFormat.yMMMd(locale).format(delivery.date),
      onTap: () => onEdit(delivery),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          _quantityPill(context.ink, delivery.quantity),
          IconButton(
            icon: const Icon(PhosphorIconsBold.x, size: 18),
            tooltip: Locales.string(context, 'inventory.remove_delivery'),
            onPressed: () => onRemove(delivery),
          ),
        ],
      ),
    );
  }

  Widget _quantityPill(InsulinkColors colors, int quantity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: ShapeDecoration(
        color: colors.panelRaised,
        shape: const StadiumBorder(),
      ),
      child: Text(
        '+$quantity',
        style: InkText.label.copyWith(
          fontWeight: FontWeight.w800,
          color: colors.accent,
        ),
      ),
    );
  }
}
