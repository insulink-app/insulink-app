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

/// A whole-minute span as a compact "1h 20min" / "45min" / "2h" — never a bare
/// "80min". Language-neutral units.
String sportMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) {
    return '${rest}min';
  }
  if (rest == 0) {
    return '${hours}h';
  }
  return '${hours}h ${rest}min';
}
