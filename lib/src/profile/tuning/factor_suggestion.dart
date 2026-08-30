import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/tuning/factor_regression.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';

/// What the clean doses say about one setting.
class FactorSuggestion {
  const FactorSuggestion({
    required this.current,
    required this.suggested,
    required this.samples,
    this.measured = true,
  });

  final int current;

  /// The proposal, already limited, snapped to the setting's own step and held
  /// inside the range the setting allows.
  final int suggested;

  /// How many doses it came from. Shown, because a number from five doses is a
  /// different thing from one built on forty.
  final int samples;

  /// Whether this was read off the windows directly, or inferred across them by
  /// [CorrectionFactorFit]. The card says which, because the two are not equally
  /// strong evidence and the user is the one deciding whether to adopt it.
  final bool measured;

  bool get isChange => suggested != current;
}

/// Suggests the three bolus settings from the dose windows.
///
/// The counterpart of `BasalSuggestion`, and it works the same way: a window is
/// not required to be quiet, it is required to be MEASURED. What else acted in
/// it — insulin still working from an earlier dose, the automation, a second
/// meal — is carried on the [TuningDose] by [TuningModel] and goes into the
/// arithmetic, rather than disqualifying the window.
///
/// The arithmetic is the bolus calculator's own, read backwards:
///
///  * **correction factor**: glucose fell by D mg/dL while `insulinActing` units
///    were working, so one unit lowered `D / insulinActing`;
///  * **carbohydrate factor**: the insulin that the food actually needed is the
///    insulin that acted, plus whatever was missing for the drift
///    (`drift / correctionFactor`). The ratio is the grams absorbed divided by
///    that;
///  * **insulin duration**: how long the correction took to reach its lowest
///    point, which is the length of the action being asked about.
///
/// The two model terms are linear approximations (see [TuningModel]), so a
/// single window says little. The median over at least [minSamples] of them, and
/// the cap below, are what make a proposal out of them.
///
/// Nothing here is applied. Each number is offered next to the one in use, and
/// it takes a deliberate tap to adopt it.
class FactorSuggestions {
  const FactorSuggestions({
    required this.correctionFactor,
    required this.carbFactor,
    required this.insulinDurationH,
  });

  final int correctionFactor;
  final int carbFactor;
  final int insulinDurationH;

  /// Windows needed before a setting is worth a word. Higher than the basal
  /// tuning's three, because a dose is one event where an hour of the day pools
  /// a whole night from each day.
  static const int minSamples = 5;

  /// There is deliberately NO per-run cap here, unlike the basal tuning.
  ///
  /// There used to be one, a fifth of the value in use, and it did not hold
  /// anything back: pressing the button three times walked to the same number
  /// anyway, one step per press. A guard that three taps bypass is not a guard,
  /// it is friction, and it made the analysis look like it kept changing its
  /// mind. So a proposal is now the measurement itself.
  ///
  /// What actually holds it down is unchanged and is about the EVIDENCE rather
  /// than the size of the move: [minSamples] windows before anything is said,
  /// the median so one dose cannot carry a setting, the standard-error refusal
  /// in [CorrectionFactorFit], the setting's own range, and the fact that
  /// nothing is adopted without a person reading both numbers and tapping.

  /// The least a window must have absorbed before it says anything about the
  /// carbohydrate factor. Below that the estimate of the food itself is the
  /// biggest term in the arithmetic.
  static const double minCarbsAbsorbed = 20;

  /// mg/dL that one unit lowered.
  ///
  /// Preferred from corrections, where it is simply read off: a dose with no
  /// food of its own is the only window in which the fall belongs to the insulin
  /// alone.
  ///
  /// Failing that it is INFERRED across the meal windows by
  /// [CorrectionFactorFit], which is what makes the setting reachable for
  /// somebody who never boluses without eating. That fit refuses itself where
  /// the insulin only ever followed the carbohydrates, so a null here still
  /// means "these windows cannot say", never "assumed".
  FactorSuggestion? correction(List<TuningDose> doses) {
    final drops = <double>[];
    for (final dose in doses.where((dose) => dose.isCorrection)) {
      if (dose.insulinActing <= 0) {
        continue;
      }
      final drop = (dose.startMgdl - dose.endMgdl) / dose.insulinActing;
      if (drop > 0) {
        drops.add(drop);
      }
    }
    final measured = _from(
      values: drops,
      current: correctionFactor,
      step: ProfileBolusState.correctionStep,
      lowest: ProfileBolusState.minCorrection,
      highest: ProfileBolusState.maxCorrection,
    );
    return measured ?? _correctionFromMeals(doses);
  }

  /// The correction factor the meal windows imply, marked as inferred.
  FactorSuggestion? _correctionFromMeals(List<TuningDose> doses) {
    final fit = CorrectionFactorFit(doses);
    final perUnit = fit.mgdlPerUnit;
    if (perUnit == null) {
      return null;
    }
    final bounded = _from(
      values: [perUnit],
      current: correctionFactor,
      step: ProfileBolusState.correctionStep,
      lowest: ProfileBolusState.minCorrection,
      highest: ProfileBolusState.maxCorrection,
      atLeast: 1,
    );
    if (bounded == null) {
      return null;
    }
    return FactorSuggestion(
      current: bounded.current,
      suggested: bounded.suggested,
      samples: fit.samples,
      measured: false,
    );
  }

  /// Grams that one unit covered, from the meal windows.
  ///
  /// The drift is converted to the insulin that was missing at the CURRENT
  /// correction factor, so a meal that ended high is measured against the dose
  /// it should have been rather than the one it was.
  FactorSuggestion? carb(List<TuningDose> doses) {
    final ratios = <double>[];
    for (final dose in doses.where((dose) => !dose.isCorrection)) {
      final needed = dose.insulinActing + dose.drift / correctionFactor;
      if (needed > 0 && dose.carbsAbsorbed >= minCarbsAbsorbed) {
        ratios.add(dose.carbsAbsorbed / needed);
      }
    }
    return _from(
      values: ratios,
      current: carbFactor,
      step: ProfileBolusState.carbStep,
      lowest: ProfileBolusState.minCarb,
      highest: ProfileBolusState.maxCarb,
    );
  }

  /// Hours a dose took to finish working, from every window whose fall could be
  /// followed to its end.
  ///
  /// Meal doses count here, unlike for the correction factor. The end of a
  /// meal's fall is the same event as the end of a correction's: the food is
  /// long absorbed by then, so where glucose stops falling is where the insulin
  /// stopped working. Without that, anybody who always boluses with food could
  /// never get an answer for this setting.
  FactorSuggestion? duration(List<TuningDose> doses) {
    final hours = <double>[];
    for (final dose in doses) {
      final minutes = dose.minutesToLowest;
      if (minutes != null) {
        hours.add(minutes / Duration.minutesPerHour);
      }
    }
    return _from(
      values: hours,
      current: insulinDurationH,
      step: ProfileBolusState.insulinDurationStep,
      lowest: ProfileBolusState.minInsulinDuration,
      highest: ProfileBolusState.maxInsulinDuration,
    );
  }

  /// The median of [values], held near the value in use and put on the
  /// setting's own grid. The median rather than the mean, so one unusual dose
  /// cannot carry a setting on its own.
  FactorSuggestion? _from({
    required List<double> values,
    required int current,
    required int step,
    required int lowest,
    required int highest,
    int? atLeast,
  }) {
    if (values.length < (atLeast ?? minSamples)) {
      return null;
    }
    return FactorSuggestion(
      current: current,
      suggested: _onGrid(_median(values), step, lowest, highest),
      samples: values.length,
    );
  }

  int _onGrid(double value, int step, int lowest, int highest) =>
      ((value / step).round() * step).clamp(lowest, highest);

  double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
