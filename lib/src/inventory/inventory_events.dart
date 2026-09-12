import 'inventory_item.dart';

enum InventoryEventKind { delivery, runOut }

/// A dated thing to show on the calendar/agenda: a delivery arriving or a
/// supply projected to run out. Derived from the items, never stored.
class InventoryEvent {
  const InventoryEvent({
    required this.kind,
    required this.date,
    required this.itemName,
    this.quantity,
  });

  final InventoryEventKind kind;
  final DateTime date;
  final String itemName;
  final int? quantity;

  /// All upcoming events across [items], sorted by date. Run-out events are
  /// only meaningful while consumption is happening, so items with no rate
  /// contribute none.
  static List<InventoryEvent> upcoming(
    List<InventoryItem> items,
    DateTime now,
  ) {
    final events = <InventoryEvent>[];
    for (final item in items) {
      for (final delivery in item.deliveries) {
        if (delivery.atEpochMs >= now.millisecondsSinceEpoch) {
          events.add(
            InventoryEvent(
              kind: InventoryEventKind.delivery,
              date: delivery.date,
              itemName: item.name,
              quantity: delivery.quantity,
            ),
          );
        }
      }
      final runOut = item.runOutDate(now);
      if (runOut != null) {
        events.add(
          InventoryEvent(
            kind: InventoryEventKind.runOut,
            date: runOut,
            itemName: item.name,
          ),
        );
      }
    }
    events.sort((left, right) => left.date.compareTo(right.date));
    return events;
  }
}

/// True when [a] and [b] fall on the same calendar day.
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
