import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// Every source of insulin still working, in one place.
///
/// It exists because there were two answers to that question and they disagreed.
/// The bolus calculator counted the meal log alone, while the automation counted
/// the meal log PLUS what it had itself added above the user's basal schedule.
/// So while the automation ran an elevated temporary rate, the insulin it had
/// put in was real, was in the body, and was invisible to the calculator, which
/// therefore suggested a correction that much too large. At the configured
/// ceilings that is up to 4 U, around 140 mg/dL of correction nobody needed.
///
/// **Scheduled basal is deliberately NOT counted.** It is maintenance insulin
/// offsetting the glucose the liver releases, it runs whether anything is
/// deciding or not, and a body on its own schedule is in equilibrium with it.
/// Counting it would have the calculator refuse a correction because "12 units
/// went in today", which is the error in the opposite direction.
///
/// What IS counted is the **deviation** from that schedule: insulin the
/// automation added on top. That is genuinely extra and has to be subtracted
/// from any correction laid on top of it.
///
/// Only a POSITIVE deviation counts. A loop running below schedule is
/// withholding background insulin, which is not the same as removing insulin
/// from the body, and treating it as negative insulin on board would INFLATE the
/// next suggestion on the strength of a dose nobody gave.
class InsulinOnBoard {
  const InsulinOnBoard(this.duration);

  /// How long a dose keeps acting, from the bolus profile.
  final Duration duration;

  /// The parts, kept apart so a screen can show what it subtracted and why.
  InsulinOnBoardParts parts(
    List<Meal> meals, {
    PodStore? pod,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return InsulinOnBoardParts(
      boluses: ActiveInsulin(duration).units(meals, now: at),
      automation: pod?.loopIobUnits(duration, now: at) ?? 0,
      unconfirmed: pod?.unconfirmedBolusUnits(duration, now: at) ?? 0,
    );
  }

  /// Everything on board, which is what a dose has to be judged against.
  double total(List<Meal> meals, {PodStore? pod, DateTime? now}) =>
      parts(meals, pod: pod, now: now).total;
}

/// Insulin on board, split by where it came from.
class InsulinOnBoardParts {
  const InsulinOnBoardParts({
    required this.boluses,
    required this.automation,
    required this.unconfirmed,
  });

  /// Doses the user chose, from the meal log. Includes pump boluses, which are
  /// written there once the pod names them back.
  final double boluses;

  /// What the automation added above the user's basal schedule.
  final double automation;

  /// Doses the pod never confirmed. Counted as delivered here: a dose that may
  /// be in the body is one no correction should be stacked on top of, and the
  /// user was told at the time to check the pod.
  final double unconfirmed;

  double get total => boluses + automation + unconfirmed;

  /// Insulin from anywhere other than the user's own logged doses. Worth naming
  /// because it is the part nobody typed in and would otherwise go unnoticed.
  double get beyondBoluses => automation + unconfirmed;
}
