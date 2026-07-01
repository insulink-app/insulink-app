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
