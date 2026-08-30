import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/profile/tuning/tuning_dose.dart';

/// Runs the three bolus suggestions until they stop moving each other.
///
/// The three are not independent, which is why adopting all of them and pressing
/// again used to produce another round of changes:
///
///  * the carbohydrate factor is measured against the CORRECTION factor, which
///    converts a window's drift into the insulin that was missing from it;
///  * every window's `insulinActing` comes from the INSULIN DURATION, so
///    changing that changes what both factors are measured against, and even
///    which windows are usable.
///
/// So the settings are solved rather than nudged: each round recomputes the
/// suggestions with the previous round's answers in place, until a round changes
/// nothing. What the card offers is that fixed point, so one press is the whole
/// journey and the press after it finds nothing left to do.
///
/// ponytail: plain fixed-point iteration with a round cap, no damping and no
/// convergence proof. Ceiling: a pathological log could oscillate between two
/// answers, in which case the last round is shown, which is no worse than the
/// single round it replaced. Upgrade path if that is ever seen: keep the round
/// whose settings reproduce themselves most closely.
class SettledFactors {
  const SettledFactors({
    required this.windowsFor,
    required this.correctionFactor,
    required this.carbFactor,
    required this.insulinDurationH,
  });

  /// The dose windows for a given insulin duration. A function rather than a
  /// list, because the duration decides what "insulin acting" means and so has
  /// to be able to rebuild them.
  final List<TuningDose> Function(int insulinDurationH) windowsFor;

  /// What the user runs today. Every suggestion is reported against these, not
  /// against the working values a round happens to be using.
  final int correctionFactor;
  final int carbFactor;
  final int insulinDurationH;

  /// Rounds before the answer is taken as it stands. Three settings that each
  /// move the others settle in two or three; more than this is an oscillation,
  /// not a slow approach.
  static const int maxRounds = 5;

  /// The settled proposals, keyed by the setting they are about. A setting the
  /// data cannot answer for is absent.
  Map<String, FactorSuggestion> solve() {
    final cache = <int, List<TuningDose>>{};
    var correction = correctionFactor;
    var carb = carbFactor;
    var duration = insulinDurationH;
    var found = <String, FactorSuggestion>{};
    for (var round = 0; round < maxRounds; round++) {
      final windows = cache.putIfAbsent(duration, () => windowsFor(duration));
      final suggestions = FactorSuggestions(
        correctionFactor: correction,
        carbFactor: carb,
        insulinDurationH: duration,
      );
      found = _reported({
        'correction': suggestions.correction(windows),
        'carb': suggestions.carb(windows),
        'duration': suggestions.duration(windows),
      });
      final nextCorrection = found['correction']?.suggested ?? correction;
      final nextCarb = found['carb']?.suggested ?? carb;
      final nextDuration = found['duration']?.suggested ?? duration;
      if (nextCorrection == correction &&
          nextCarb == carb &&
          nextDuration == duration) {
        break;
      }
      correction = nextCorrection;
      carb = nextCarb;
      duration = nextDuration;
    }
    return found;
  }

  /// The round's answers, restated against what the USER has set, so the row
  /// shows the move they would actually be making.
  Map<String, FactorSuggestion> _reported(
    Map<String, FactorSuggestion?> round,
  ) {
    final current = {
      'correction': correctionFactor,
      'carb': carbFactor,
      'duration': insulinDurationH,
    };
    final reported = <String, FactorSuggestion>{};
    round.forEach((setting, suggestion) {
      if (suggestion != null) {
        reported[setting] = FactorSuggestion(
          current: current[setting]!,
          suggested: suggestion.suggested,
          samples: suggestion.samples,
          measured: suggestion.measured,
        );
      }
    });
    return reported;
  }
}
