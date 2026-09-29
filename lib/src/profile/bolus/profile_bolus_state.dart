import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-tunable bolus-calculator settings. Two linear factors drive the
/// suggested dose:
///   * [correctionFactor] — mg/dL of glucose lowered per 1 unit of insulin
///     (insulin-sensitivity factor). Default 35 mg/dL per unit.
///   * [carbFactor] — grams of carbohydrate covered per 1 unit of insulin
///     (carb ratio). Default 15 g per unit.
///
/// Plus two safety/behaviour limits:
///   * [maxBolus] — the largest dose the injection sheet accepts, so a slipped
///     decimal point can't be logged. Default 10 units.
///   * [insulinDurationH] — how long a bolus keeps acting, driving the active
///     insulin (IOB) readout. Default 3 hours.
///
/// Provided above the page tree (see `main.dart`) so the injection sheet and
/// profile page can observe it; persisted in secure storage.
class ProfileBolusState extends ChangeNotifier {
  static const _kCorrection = 'bolus_correction_factor';
  static const _kCarb = 'bolus_carb_factor';
  static const _kMaxBolus = 'bolus_max';
  static const _kInsulinDuration = 'bolus_insulin_duration_h';

  // Defaults — mirror the factors requested for the calculator.
  static const defCorrection = 35; // mg/dL per unit
  static const defCarb = 15; // g per unit
  static const defMaxBolus = 10; // units
  static const defInsulinDuration = 3; // hours

  /// Allowed adjustment range + step for the sliders.
  static const minCorrection = 10;
  static const maxCorrection = 100;
  static const correctionStep = 5;

  static const minCarb = 5;
  static const maxCarb = 30;
  static const carbStep = 1;

  static const minMaxBolus = 1;
  static const maxMaxBolus = 50;
  static const maxBolusStep = 1;

  static const minInsulinDuration = 2;
  static const maxInsulinDuration = 8;
  static const insulinDurationStep = 1;

  int _correctionFactor;
  int _carbFactor;
  int _maxBolus;
  int _insulinDurationH;

  ProfileBolusState({
    required this._correctionFactor,
    required this._carbFactor,
    required this._maxBolus,
    required this._insulinDurationH,
  });

  int get correctionFactor => _correctionFactor;

  int get carbFactor => _carbFactor;

  /// Upper bound for a single logged bolus, in units.
  int get maxBolus => _maxBolus;

  /// How many hours a bolus stays active, as a [Duration] for the active-insulin
  /// calculation.
  Duration get insulinDuration => Duration(hours: _insulinDurationH);

  int get insulinDurationH => _insulinDurationH;

  static const _storage = FlutterSecureStorage();

  Future<void> setCorrectionFactor(int v) async {
    v = v.clamp(minCorrection, maxCorrection);
    if (v == _correctionFactor) {
      return;
    }
    _correctionFactor = v;
    notifyListeners();
    await _storage.write(key: _kCorrection, value: '$v');
  }

  Future<void> setCarbFactor(int v) async {
    v = v.clamp(minCarb, maxCarb);
    if (v == _carbFactor) {
      return;
    }
    _carbFactor = v;
    notifyListeners();
    await _storage.write(key: _kCarb, value: '$v');
  }

  Future<void> setMaxBolus(int v) async {
    v = v.clamp(minMaxBolus, maxMaxBolus);
    if (v == _maxBolus) {
      return;
    }
    _maxBolus = v;
    notifyListeners();
    await _storage.write(key: _kMaxBolus, value: '$v');
  }

  Future<void> setInsulinDurationH(int v) async {
    v = v.clamp(minInsulinDuration, maxInsulinDuration);
    if (v == _insulinDurationH) {
      return;
    }
    _insulinDurationH = v;
    notifyListeners();
    await _storage.write(key: _kInsulinDuration, value: '$v');
  }

  /// Suggested bolus (units) for [carbs] g of carbohydrate at the current
  /// [glucoseMgdl], correcting toward [targetMgdl], less the [iobUnits] of
  /// insulin still active from earlier boluses (see [ActiveInsulin]).
  ///
  /// [iobUnits] is REQUIRED rather than defaulting to 0 on purpose: a caller that
  /// forgets it would silently get the old stacking-prone dose, and there are
  /// only two call sites (the injection sheet and the predictive high advisory) —
  /// both of which must agree on the number they show.
  ///
  /// [cobGrams] (see `CarbsOnBoard`) may default to 0: leaving it out only keeps
  /// the full negative correction, which is the cautious direction.
  double suggestedBolus({
    required double carbs,
    required int glucoseMgdl,
    required int targetMgdl,
    required double iobUnits,
    double cobGrams = 0,
  }) {
    final meal = carbs / _carbFactor;
    final correction = (glucoseMgdl - targetMgdl) / _correctionFactor;
    final suggestion = correction > 0
        ? meal + _correctionAfterIob(correction, iobUnits)
        : meal + _lowCorrectionAfterCob(correction, cobGrams, iobUnits);
    return suggestion > 0 ? suggestion : 0;
  }

  /// [correction] with the active insulin taken off it.
  ///
  /// Active insulin is already working on the CURRENT glucose, so laying a second
  /// full correction on top of it is the classic stacking hypo — hence the
  /// subtraction. It never goes below zero, and it never touches the meal part of
  /// the dose: those carbs are new and still need covering, so letting residual
  /// insulin swallow a meal bolus would only trade a hypo for a spike.
  ///
  /// Only for a POSITIVE correction; under target see [_lowCorrectionAfterCob].
  double _correctionAfterIob(double correction, double iobUnits) {
    final remaining = correction - iobUnits;
    return remaining > 0 ? remaining : 0;
  }

  /// A NEGATIVE [correction] (glucose under target) with the carbs already on
  /// their way up taken off it.
  ///
  /// Under target the correction reduces the meal dose — a real "you are low,
  /// take less". But it used to be charged in FULL on every meal logged while
  /// low: the carbs eaten to treat the low were still being absorbed, yet the
  /// next meal lost the whole deficit again, so repeated meals in one low got
  /// almost no insulin. Only carbs NOT already covered by active insulin count
  /// ([cobGrams] as units minus [iobUnits], never below 0), so a meal that was
  /// fully bolused before the low lifts nothing. It never turns positive: pending
  /// carbs can cancel the low, never add a correction on top.
  double _lowCorrectionAfterCob(
    double correction,
    double cobGrams,
    double iobUnits,
  ) {
    final uncoveredCarbs = cobGrams / _carbFactor - iobUnits;
    final lifted = correction + (uncoveredCarbs > 0 ? uncoveredCarbs : 0);
    return lifted < 0 ? lifted : 0;
  }

  /// Grams of fast carbs to raise [glucoseMgdl] up to [targetMgdl]. Derived from
  /// the same two factors: 1 unit covers [carbFactor] g AND lowers glucose by
  /// [correctionFactor] mg/dL, so [carbFactor] g ≈ raises glucose by
  /// [correctionFactor] mg/dL. One-sided (0 at/above target).
  double suggestedRescueCarbs({
    required int glucoseMgdl,
    required int targetMgdl,
  }) {
    final rise = targetMgdl - glucoseMgdl;
    final grams = rise * _carbFactor / _correctionFactor;
    return grams > 0 ? grams : 0;
  }

  // ---- Persistence ----

  static int _readInt(String? raw, int fallback) =>
      raw == null ? fallback : (int.tryParse(raw) ?? fallback);

  /// Read all persisted settings (defaults applied per field).
  static Future<ProfileBolusState> load() async {
    final all = await _storage.readAll();
    final fixed = _readInt(all[_kCorrection], defCorrection);
    return ProfileBolusState(
      correctionFactor: fixed,
      carbFactor: _readInt(all[_kCarb], defCarb),
      maxBolus: _readInt(all[_kMaxBolus], defMaxBolus),
      insulinDurationH: _readInt(all[_kInsulinDuration], defInsulinDuration),
    );
  }
}
