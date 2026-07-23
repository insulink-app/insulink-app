import 'package:flutter/material.dart';
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
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.package, size: 28),
          color: const Color(0xFFB3B3B3),
          onPressed: () => openInventoryPage(context),
        ),
        if (needsAttention)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).appBarTheme.backgroundColor ??
                      Theme.of(context).scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
