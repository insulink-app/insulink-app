import 'package:flutter/material.dart';
import 'package:insulink/src/base/long_press_reorder.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

import '../localization/locale_text.dart';
import 'inventory_calendar_page.dart';
import 'inventory_item.dart';
import 'inventory_item_card.dart';
import 'inventory_item_editor.dart';
import 'inventory_state.dart';

/// Opens the inventory page on top of the current tab (from the header button).
void openInventoryPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const InventoryPage()));
}

/// Inventory page: the tracked items with their forecast. The calendar of
/// upcoming events lives on its own page, reached via the header icon.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  @override
  void initState() {
    super.initState();
    // The service isolate may have auto-decremented stock for a new sensor
    // while the app was closed; re-read the store so it shows through.
    context.read<InventoryState>().refresh();
  }

  void _openEditor(BuildContext context, {InventoryItem? item}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryItemEditor(existing: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<InventoryState>().items;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('inventory.label'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.calendarBlank),
            onPressed: () => openInventoryCalendarPage(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // No hero flight: the shared default tag makes it morph into the
        // injection page's FAB when navigating between them.
        heroTag: null,
        onPressed: () => _openEditor(context),
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(child: LocaleText('inventory.empty')),
            )
          : ReorderableListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              onReorderItem: (oldIndex, newIndex) =>
                  context.read<InventoryState>().reorder(oldIndex, newIndex),
              buildDefaultDragHandles: false,
              children: [
                for (final item in items)
                  Padding(
                    key: ValueKey(item.id),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: InventoryItemCard(
                      item: item,
                      onEdit: () => _openEditor(context, item: item),
                    ),
                  ),
              ].pickedUpByLongPress(),
            ),
    );
  }
}
