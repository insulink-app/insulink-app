import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'inventory_events.dart';

/// A minimal month grid with a dot on any day that has an inventory event, plus
/// month navigation. Selecting a day lifts it out via [onDaySelected] so the
/// body can list that day's events. No calendar package — just DateTime maths.
// ponytail: minimaler Monats-Grid, table_calendar erst wenn mehr Ansichten nötig.
class InventoryCalendar extends StatefulWidget {
  const InventoryCalendar({
    super.key,
    required this.events,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final List<InventoryEvent> events;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<InventoryCalendar> createState() => _InventoryCalendarState();
}

class _InventoryCalendarState extends State<InventoryCalendar> {
  late DateTime _month =
      DateTime(widget.selectedDay.year, widget.selectedDay.month);

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  bool _hasEvent(DateTime day) =>
      widget.events.any((event) => sameDay(event.date, day));

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final scheme = Theme.of(context).colorScheme;
    final leadingBlanks = DateTime(_month.year, _month.month).weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.caretLeft, size: 18),
              onPressed: () => _shiftMonth(-1),
            ),
            Text(
              DateFormat.yMMMM(locale).format(_month),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.caretRight, size: 18),
              onPressed: () => _shiftMonth(1),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final label in _weekdayLabels(locale))
              Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            for (var blank = 0; blank < leadingBlanks; blank++)
              const SizedBox.shrink(),
            for (var dayNumber = 1; dayNumber <= daysInMonth; dayNumber++)
              _dayCell(
                DateTime(_month.year, _month.month, dayNumber),
                scheme,
              ),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(DateTime day, ColorScheme scheme) {
    final selected = sameDay(day, widget.selectedDay);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => widget.onDaySelected(day),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
          if (_hasEvent(day))
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  /// Monday-first short weekday headers in the active locale.
  List<String> _weekdayLabels(String locale) {
    final format = DateFormat.E(locale);
    return [
      for (var weekday = 0; weekday < 7; weekday++)
        format.format(DateTime(2024, 1, 1).add(Duration(days: weekday))),
    ];
  }
}
