/// A compact date+time label for a logged meal, e.g. "Heute 12:45" is left to
/// the caller — here we keep it locale-neutral: "11.07. 12:45", dropping the
/// date when the meal is from today so recent entries read cleanly.
String mealTimeLabel(DateTime time) {
  final clock = '${_two(time.hour)}:${_two(time.minute)}';
  final now = DateTime.now();
  final sameDay =
      now.year == time.year && now.month == time.month && now.day == time.day;
  if (sameDay) {
    return clock;
  }
  return '${_two(time.day)}.${_two(time.month)}. $clock';
}

String _two(int value) => value.toString().padLeft(2, '0');
