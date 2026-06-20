import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-tunable bolus-calculator factors. Two linear factors drive the
/// suggested dose:
///   * [correctionFactor] — mg/dL of glucose lowered per 1 unit of insulin
///     (insulin-sensitivity factor). Default 35 mg/dL per unit.
///   * [carbFactor] — grams of carbohydrate covered per 1 unit of insulin
///     (carb ratio). Default 15 g per unit.
///
/// Provided above the page tree (see `main.dart`) so the injection sheet and
/// profile page can observe it; persisted in secure storage.
class ProfileBolusState extends ChangeNotifier {
  static const _kCorrection = 'bolus_correction_factor';
  static const _kCarb = 'bolus_carb_factor';

  // Defaults — mirror the factors requested for the calculator.
  static const defCorrection = 35; // mg/dL per unit
  static const defCarb = 15; // g per unit

  /// Allowed adjustment range + step for the sliders.
  static const minCorrection = 10;
  static const maxCorrection = 100;
  static const correctionStep = 5;

  static const minCarb = 5;
  static const maxCarb = 30;
  static const carbStep = 1;

  int _correctionFactor;
  int _carbFactor;

  ProfileBolusState({required this._correctionFactor, required this._carbFactor});

  int get correctionFactor => _correctionFactor;
  int get carbFactor => _carbFactor;

  static const _storage = FlutterSecureStorage();

  Future<void> setCorrectionFactor(int v) async {
    v = v.clamp(minCorrection, maxCorrection);
    if (v == _correctionFactor) return;
    _correctionFactor = v;
    notifyListeners();
    await _storage.write(key: _kCorrection, value: '$v');
  }

  Future<void> setCarbFactor(int v) async {
    v = v.clamp(minCarb, maxCarb);
    if (v == _carbFactor) return;
    _carbFactor = v;
    notifyListeners();
    await _storage.write(key: _kCarb, value: '$v');
  }

  /// Suggested bolus (units) for [carbs] g of carbohydrate at the current
  /// [glucoseMgdl], correcting toward [targetMgdl]. Correction is one-sided:
  /// glucose at/below target contributes no correction dose.
  double suggestedBolus({
    required double carbs,
    required int glucoseMgdl,
    required int targetMgdl,
  }) {
    final meal = carbs / _carbFactor;
    final correction = (glucoseMgdl - targetMgdl) / _correctionFactor;
    final suggestion = meal + correction;
    return suggestion > 0 ? suggestion : 0;
  }

  // ---- Persistence ----

  static int _readInt(String? raw, int fallback) =>
      raw == null ? fallback : (int.tryParse(raw) ?? fallback);

  /// Read all persisted factors (defaults applied per field).
  static Future<ProfileBolusState> load() async {
    final all = await _storage.readAll();
    return ProfileBolusState(
      correctionFactor: _readInt(all[_kCorrection], defCorrection),
      carbFactor: _readInt(all[_kCarb], defCarb),
    );
  }
}
