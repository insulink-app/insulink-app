import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

import '../inventory/inventory_body.dart';
import '../inventory/inventory_state.dart';

/// Header shortcut to the inventory page, with a red dot when any tracked item
/// is running low or heading for a shortage before its next delivery.
class HeaderInventoryButton extends StatelessWidget {
  const HeaderInventoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final needsAttention = context.watch<InventoryState>().hasWarning;
    return HeaderIconButton(
      icon: PhosphorIconsRegular.package,
      labelKey: 'inventory.label',
      statusColor: needsAttention ? context.ink.low : null,
      onTap: () => openInventoryPage(context),
    );
  }
}
