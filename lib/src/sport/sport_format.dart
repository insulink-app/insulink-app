import 'package:intl/intl.dart';

/// German number formatting for the Sport pages: '.' as thousands separator and
/// ',' as decimal separator (e.g. 1.234 or 6,20). The Sport area uses German
/// formatting regardless of the app locale.
String sportInt(num value) => NumberFormat.decimalPattern('de').format(value);

/// German decimal with a fixed number of [decimals] (e.g. 72,5 or 6,20).
String sportDecimal(num value, int decimals) {
  final format = NumberFormat.decimalPattern('de')
    ..minimumFractionDigits = decimals
    ..maximumFractionDigits = decimals;
  return format.format(value);
}

/// A duration as a clock: "MM:SS", widening to "HH:MM:SS" once it reaches an
/// hour. Minutes and seconds are always two digits.
String sportClock(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  if (hours == 0) {
    return '$mm:$ss';
  }
  return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
}
