import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// Glucose numbers for the overview, in the user's unit and German notation
/// ("137", "6,7", "+0,3"), like every other number on the redesigned page.
///
/// Separate from [ProfileGlucoseState.format] on purpose: that one also feeds
/// the home-screen widget from the service isolate and keeps its plain format.
class GlucoseDisplayFormat {
  const GlucoseDisplayFormat(this.glucose);

  final ProfileGlucoseState glucose;

  bool get _mgdl => glucose.unit == GlucoseUnit.mgdl;

  /// Whole mg/dL, or mmol/L with one decimal.
  String value(int mgdl) {
    if (_mgdl) {
      return '$mgdl';
    }
    return sportDecimal(glucose.toDisplay(mgdl), 1);
  }

  /// Signed rate per minute: one decimal in mg/dL, two in mmol/L.
  String rate(double mgdlPerMin) {
    final display = glucose.toDisplay(1) * mgdlPerMin;
    final sign = display >= 0 ? '+' : '-';
    return '$sign${sportDecimal(display.abs(), _mgdl ? 1 : 2)}';
  }
}
