/// Day arithmetic the demo generators share: the last N local days up to
/// [now], and a wall-clock time on one of them.
class DemoCalendar {
  DemoCalendar(this.now);

  final DateTime now;

  late final DateTime today = DateTime(now.year, now.month, now.day);

  /// The last [count] days, oldest first, today included.
  List<DateTime> lastDays(int count) => [
    for (var back = count - 1; back >= 0; back--)
      DateTime(today.year, today.month, today.day - back),
  ];

  /// [day] at the fractional [hour], e.g. 7.5 for half past seven.
  DateTime at(DateTime day, double hour) =>
      day.add(Duration(minutes: (hour * 60).round()));

  /// Whether [time] has already happened.
  bool isPast(DateTime time) => time.isBefore(now);

  /// The `yyyy-MM-dd` key the API uses for day records.
  String dateKey(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date';
  }
}
