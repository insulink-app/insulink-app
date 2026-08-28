import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/bolus/profile_bolus_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// Everything the automated loop is allowed to do, in one value.
///
/// Composed from settings that already exist rather than duplicated: the
/// correction factor and insulin duration come from the bolus profile, the
/// target from the glucose profile. A second copy of those would drift from the
/// ones the bolus calculator uses, and then the automation and the user would be
/// working to different numbers.
///
/// Only the three genuinely loop-specific values are its own: the rate ceiling,
/// the insulin-on-board ceiling, and the glucose it stops delivering at.
///
/// [isUsable] is checked before any cycle runs. A limit set that does not make
/// sense (a suspend threshold above target, a zero correction factor) cannot be
/// clamped into one that does, so the loop refuses to run instead of guessing.
class LoopLimits {
  const LoopLimits({
    required this.targetMgdl,
    required this.suspendBelowMgdl,
    required this.correctionFactorMgdl,
    required this.insulinDuration,
    required this.maxUnitsPerHour,
    required this.maxIobUnits,
  });

  /// Reads the current limits, filling in defaults for anything unset.
  static Future<LoopLimits> load() async {
    const storage = FlutterSecureStorage();
    final all = await storage.readAll();
    final bolus = await ProfileBolusState.load();
    final glucose = await ProfileGlucoseState.load();
    return LoopLimits(
      targetMgdl: glucose.targetMid,
      suspendBelowMgdl:
          int.tryParse(all[keySuspendBelow] ?? '') ?? defaultSuspendBelowMgdl,
      correctionFactorMgdl: bolus.correctionFactor,
      insulinDuration: Duration(hours: bolus.insulinDurationH),
      maxUnitsPerHour:
          double.tryParse(all[keyMaxRate] ?? '') ?? defaultMaxUnitsPerHour,
      maxIobUnits: double.tryParse(all[keyMaxIob] ?? '') ?? defaultMaxIobUnits,
    );
  }

  static const String keySuspendBelow = 'loop_suspend_below_mgdl';
  static const String keyMaxRate = 'loop_max_units_per_hour';
  static const String keyMaxIob = 'loop_max_iob_units';

  /// Deliberately well above the usual hypo alarm line. This is not the value
  /// the user is warned at, it is the value the automation stops adding insulin
  /// at, and it has to leave room for the insulin already given to keep acting.
  static const int defaultSuspendBelowMgdl = 85;


  static const double defaultMaxUnitsPerHour = 3.0;
  static const double defaultMaxIobUnits = 5.0;

  /// The ceiling the rate ceiling itself is capped at, matching the pod's own.
  static const double podMaxUnitsPerHour = 30.0;

  /// How far ahead the trend is projected when deciding. Equal to [fuse] on
  /// purpose: the question each cycle asks is what happens over exactly the
  /// stretch it is about to commit to.
  static const Duration projection = Duration(minutes: 30);

  /// How long each programmed temporary rate runs if nothing renews it.
  ///
  /// This is the fuse. When the loop stops, whatever the last cycle programmed
  /// keeps running for at most this long and then the pod falls back to the
  /// stored basal schedule on its own, with no app involved. It is also the
  /// window the hypo headroom is computed over, so the worst case that is
  /// guarded against is the fuse burning down unattended.
  ///
  /// 30 minutes because that is the shortest temporary basal the pod accepts.
  static const Duration fuse = Duration(minutes: 30);

  final int targetMgdl;
  final int suspendBelowMgdl;
  final int correctionFactorMgdl;
  final Duration insulinDuration;
  final double maxUnitsPerHour;
  final double maxIobUnits;

  /// Whether these limits are internally consistent enough to dose against.
  bool get isUsable => problem == null;

  /// What is wrong with the limits, or null when nothing is.
  String? get problem {
    if (correctionFactorMgdl <= 0) {
      return 'Correction factor must be above zero';
    }
    if (suspendBelowMgdl >= targetMgdl) {
      return 'Suspend threshold $suspendBelowMgdl must be below target $targetMgdl';
    }
    if (suspendBelowMgdl < minSuspendBelowMgdl) {
      return 'Suspend threshold $suspendBelowMgdl is below the floor of $minSuspendBelowMgdl';
    }
    if (maxUnitsPerHour <= 0 || maxUnitsPerHour > podMaxUnitsPerHour) {
      return 'Rate ceiling $maxUnitsPerHour U/h is outside 0 to $podMaxUnitsPerHour U/h';
    }
    if (maxIobUnits <= 0) {
      return 'Insulin-on-board ceiling must be above zero';
    }
    if (insulinDuration <= Duration.zero) {
      return 'Insulin duration must be above zero';
    }
    return null;
  }

  /// The lowest the suspend threshold may be set to. Below this the automation
  /// would still be adding insulin while the user is already hypoglycaemic.
  static const int minSuspendBelowMgdl = 70;
}
