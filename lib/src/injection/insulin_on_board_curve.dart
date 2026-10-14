import 'package:insulink/src/injection/active_insulin.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// Insulin on board at one moment, split by where it came from.
class InsulinOnBoardSample {
  const InsulinOnBoardSample({
    required this.at,
    required this.boluses,
    required this.microBoluses,
    required this.rate,
  });

  final DateTime at;

  /// The user's own boluses, including any the pod never confirmed.
  final double boluses;

  /// The automation's micro boluses.
  final double microBoluses;

  /// What the automation's temporary rate added above the schedule.
  final double rate;

  double get total => boluses + microBoluses + rate;
}

/// The active-insulin curve with the pump's share drawn in, not only the meals.
///
/// Every part is sampled as it WAS at each moment: a dose given later counts
/// nothing before it, and past the present only the insulin already in decays,
/// so the rate running now is never projected into insulin not yet delivered.
/// At the present itself the parts add up to [InsulinOnBoard], so the graph and
/// the number above it agree.
class InsulinOnBoardCurve {
  const InsulinOnBoardCurve(this.duration);

  /// How long a dose keeps acting.
  final Duration duration;

  /// Samples from one insulin duration back to one ahead, trimmed to where
  /// anything is on board, or empty when nothing is.
  List<InsulinOnBoardSample> samples(
    List<Meal> meals, {
    PodStore? pod,
    DateTime? now,
    Duration step = const Duration(minutes: 5),
  }) {
    final at = now ?? DateTime.now();
    final all = [
      for (
        var sample = at.subtract(duration);
        !sample.isAfter(at.add(duration));
        sample = sample.add(step)
      )
        _sampleAt(meals, pod, sample, at),
    ];
    final first = all.indexWhere((sample) => sample.total > 0);
    final last = all.lastIndexWhere((sample) => sample.total > 0);
    if (first < 0) {
      return const [];
    }
    return all.sublist(first, last + 1);
  }

  InsulinOnBoardSample _sampleAt(
    List<Meal> meals,
    PodStore? pod,
    DateTime sample,
    DateTime now,
  ) {
    return InsulinOnBoardSample(
      at: sample,
      boluses:
          ActiveInsulin(duration).unitsAt(meals, sample) +
          _unconfirmedAt(pod, sample),
      microBoluses: pod?.loopMicroBolusIobAt(duration, sample) ?? 0,
      rate:
          pod?.loopRateIobUnits(
            duration,
            at: sample,
            deliveredUntil: now.isBefore(sample) ? now : sample,
          ) ??
          0,
    );
  }

  /// Boluses whose outcome nobody could confirm, which the total counts too.
  double _unconfirmedAt(PodStore? pod, DateTime sample) {
    var units = 0.0;
    for (final bolus in pod?.unconfirmedBoluses ?? const []) {
      if (bolus.at.isAfter(sample)) {
        continue;
      }
      final elapsed = sample.difference(bolus.at).inSeconds;
      final fraction = 1 - elapsed / duration.inSeconds;
      units += bolus.units * fraction.clamp(0.0, 1.0);
    }
    return units;
  }
}
