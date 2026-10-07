import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

import '../localization/locale_text.dart';
import '../localization/locales.dart';
import 'inventory_calendar.dart';
import 'inventory_events.dart';
import 'inventory_state.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Opens the inventory calendar (from the inventory page's header icon).
void openInventoryCalendarPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const InventoryCalendarPage()),
  );
}

/// The month calendar of upcoming deliveries/run-outs with the events on the
/// selected day listed below it.
class InventoryCalendarPage extends StatefulWidget {
  const InventoryCalendarPage({super.key});

  @override
  State<InventoryCalendarPage> createState() => _InventoryCalendarPageState();
}

class _InventoryCalendarPageState extends State<InventoryCalendarPage> {
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final items = context.watch<InventoryState>().items;
    final events = InventoryEvent.upcoming(items, DateTime.now());
    final dayEvents = events
        .where((event) => sameDay(event.date, _selectedDay))
        .toList();
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('inventory.calendar'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          InventoryCalendar(
            events: events,
            selectedDay: _selectedDay,
            onDaySelected: (day) => setState(() => _selectedDay = day),
          ),
          const SizedBox(height: 8),
          for (final event in dayEvents) _EventRow(event: event),
          if (dayEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LocaleText(
                'inventory.no_events',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One event line under the calendar: an icon, the item name and, for a
/// delivery, the quantity.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final InventoryEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDelivery = event.kind == InventoryEventKind.delivery;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        isDelivery ? PhosphorIconsBold.package : PhosphorIconsBold.warning,
        color: isDelivery ? scheme.primary : context.warning,
      ),
      title: Text(event.itemName),
      subtitle: LocaleText(
        isDelivery ? 'inventory.event_delivery' : 'inventory.event_run_out',
      ),
      trailing: isDelivery
          ? Text(
              Locales.string(
                context,
                'inventory.units',
                params: ['${event.quantity}'],
              ),
            )
          : null,
    );
  }
}
