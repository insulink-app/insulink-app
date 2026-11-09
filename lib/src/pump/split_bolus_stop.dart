import 'package:insulink/src/pump/loop/loop_glucose.dart';
import 'package:insulink/src/pump/split_bolus.dart';

/// Why a due split-bolus part must not go out, as the locale key of the
/// notification that ends the plan.
///
/// The meal it was dosed for must still be in the log: deleted (a wrong entry,
/// or removed in the panel), its rest is insulin for food that did not happen.
/// A meal whose time was edited no longer matches either, and stops the plan
/// the same way, which errs on the side of less insulin.
///
/// One of them is the low guard: no part when glucose is at the user's low
/// line already, or its trend reaches it within [lookahead]. The automation
/// lowers the basal then, but the planned parts are boluses and would keep
/// coming regardless. Without usable sensor data the part still goes, exactly
/// as a pump's own extended bolus would: the user asked for it, and the guard
/// only exists to overrule that request with evidence.
class SplitBolusStop {
  const SplitBolusStop({required this.lowMgdl});

  static const lookahead = Duration(minutes: 30);

  final int lowMgdl;

  /// The reason [plan]'s due first part must not go out, or null when it may.
  String? reasonFor(
    SplitBolusPlan plan, {
    required bool hasPod,
    required bool mealLogged,
    required LoopGlucose glucose,
    required DateTime now,
  }) {
    if (!hasPod) {
      return 'alarm.split_bolus.failed';
    }
    if (!mealLogged) {
      return 'alarm.split_bolus.meal_gone';
    }
    if (plan.missedAt(now)) {
      return 'alarm.split_bolus.lapsed';
    }
    return lowAhead(glucose) ? 'alarm.split_bolus.low' : null;
  }

  bool lowAhead(LoopGlucose glucose) {
    if (!glucose.isUsable) {
      return false;
    }
    final ahead = glucose.mgdl + glucose.trendPerMinute * lookahead.inMinutes;
    return glucose.mgdl <= lowMgdl || ahead <= lowMgdl;
  }
}
