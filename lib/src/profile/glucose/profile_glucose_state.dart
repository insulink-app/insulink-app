import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Display unit for glucose values. Everything is reasoned about and stored
/// internally in **mg/dL** (the sensor's native unit); mmol/L is purely a
/// display conversion.
enum GlucoseUnit { mgdl, mmol }

extension GlucoseUnitLabel on GlucoseUnit {
  String get label => this == GlucoseUnit.mgdl ? 'mg/dL' : 'mmol/L';
}

/// mg/dL → mmol/L conversion factor (standard molar mass of glucose).
const double _mmolPerMgdl = 1 / 18.0182;

/// User-tunable glucose display + target + alarm settings. All thresholds are
/// canonical **mg/dL** integers; only the display layer converts to mmol/L.
///
/// Provided above the page tree (see `main.dart`) so the overview, chart and
/// sensor pages can observe it; persisted in secure storage. The
/// foreground-service isolate can't watch this notifier, so it reads the same
/// keys via [loadThresholds].
class ProfileGlucoseState extends ChangeNotifier {
  // Storage keys (shared with [load]/[loadThresholds]).
  static const _kUnit = 'glucose_unit';
  static const _kTargetLow = 'glucose_target_low';
  static const _kTargetHigh = 'glucose_target_high';
  static const _kUrgentLow = 'glucose_urgent_low';
  static const _kLow = 'glucose_low';
  static const _kHigh = 'glucose_high';
  static const _kUrgentHigh = 'glucose_urgent_high';

  // Defaults (mg/dL) — mirror the previously hard-wired thresholds.
  static const defTargetLow = 70;
  static const defTargetHigh = 180;
  static const defUrgentLow = 55;
  static const defLow = 70;
  static const defHigh = 180;
  static const defUrgentHigh = 250;

  /// Allowed adjustment range + step for the sliders.
  static const minMgdl = 40;
  static const maxMgdl = 300;
  static const step = 5;

  GlucoseUnit _unit;
  int _targetLow, _targetHigh;
  int _urgentLow, _low, _high, _urgentHigh;

  ProfileGlucoseState({
    required this._unit,
    required this._targetLow,
    required this._targetHigh,
    required this._urgentLow,
    required this._low,
    required this._high,
    required this._urgentHigh,
  });

  GlucoseUnit get unit => _unit;
  int get targetLow => _targetLow;
  int get targetHigh => _targetHigh;

  /// The middle of the target range — what a correction dose aims at. Lives here
  /// so the injection sheet and the predictive advisory cannot drift apart on
  /// what "target" means; they must suggest the same units for the same glucose.
  int get targetMid => ((_targetLow + _targetHigh) / 2).round();
  int get urgentLow => _urgentLow;
  int get low => _low;
  int get high => _high;
  int get urgentHigh => _urgentHigh;

  static const _storage = FlutterSecureStorage();

  Future<void> setUnit(GlucoseUnit unit) async {
    if (unit == _unit) {
      return;
    }
    _unit = unit;
    notifyListeners();
    await _storage.write(key: _kUnit, value: unit.name);
  }

  /// Target range thumbs. Kept ordered (low ≤ high) and within bounds.
  Future<void> setTargetRange(int low, int high) async {
    _targetLow = low.clamp(minMgdl, maxMgdl);
    _targetHigh = high.clamp(_targetLow, maxMgdl);
    notifyListeners();
    await _storage.write(key: _kTargetLow, value: '$_targetLow');
    await _storage.write(key: _kTargetHigh, value: '$_targetHigh');
  }

  /// Low-side alarm thumbs: urgent-low ≤ low.
  Future<void> setLowAlarms(int urgentLow, int low) async {
    _urgentLow = urgentLow.clamp(minMgdl, maxMgdl);
    _low = low.clamp(_urgentLow, maxMgdl);
    notifyListeners();
    await _storage.write(key: _kUrgentLow, value: '$_urgentLow');
    await _storage.write(key: _kLow, value: '$_low');
  }

  /// High-side alarm thumbs: high ≤ urgent-high.
  Future<void> setHighAlarms(int high, int urgentHigh) async {
    _high = high.clamp(minMgdl, maxMgdl);
    _urgentHigh = urgentHigh.clamp(_high, maxMgdl);
    notifyListeners();
    await _storage.write(key: _kHigh, value: '$_high');
    await _storage.write(key: _kUrgentHigh, value: '$_urgentHigh');
  }

  // ---- Display helpers (respect the chosen unit) ----

  /// The numeric value in the chosen unit (mg/dL as-is, or mmol/L).
  double toDisplay(int mgdl) =>
      _unit == GlucoseUnit.mgdl ? mgdl.toDouble() : mgdl * _mmolPerMgdl;

  /// Formatted value WITHOUT a unit suffix (`"120"` or `"6.7"`).
  String format(int mgdl) => _unit == GlucoseUnit.mgdl
      ? '$mgdl'
      : (mgdl * _mmolPerMgdl).toStringAsFixed(1);

  /// Formatted value WITH the unit suffix (`"120 mg/dL"` / `"6.7 mmol/L"`).
  String formatWithUnit(int mgdl) => '${format(mgdl)} ${_unit.label}';

  /// Signed per-minute trend in the chosen unit (`"+1.0"` / `"-0.1"`).
  String formatTrend(double mgdlPerMin) {
    final value = _unit == GlucoseUnit.mgdl
        ? mgdlPerMin
        : mgdlPerMin * _mmolPerMgdl;
    final digits = _unit == GlucoseUnit.mgdl ? 1 : 2;
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(digits)}';
  }

  // ---- Persistence ----

  static int _readInt(String? raw, int fallback) =>
      raw == null ? fallback : (int.tryParse(raw) ?? fallback);

  static GlucoseUnit _readUnit(String? raw) =>
      raw == GlucoseUnit.mmol.name ? GlucoseUnit.mmol : GlucoseUnit.mgdl;

  /// Read all persisted settings (defaults applied per field).
  static Future<ProfileGlucoseState> load() async {
    final all = await _storage.readAll();
    return ProfileGlucoseState(
      unit: _readUnit(all[_kUnit]),
      targetLow: _readInt(all[_kTargetLow], defTargetLow),
      targetHigh: _readInt(all[_kTargetHigh], defTargetHigh),
      urgentLow: _readInt(all[_kUrgentLow], defUrgentLow),
      low: _readInt(all[_kLow], defLow),
      high: _readInt(all[_kHigh], defHigh),
      urgentHigh: _readInt(all[_kUrgentHigh], defUrgentHigh),
    );
  }

  /// Lightweight read of just the alarm thresholds + unit, for the
  /// foreground-service isolate (which can't observe this ChangeNotifier).
  static Future<
    ({GlucoseUnit unit, int urgentLow, int low, int high, int urgentHigh})
  >
  loadThresholds() async {
    final all = await _storage.readAll();
    return (
      unit: _readUnit(all[_kUnit]),
      urgentLow: _readInt(all[_kUrgentLow], defUrgentLow),
      low: _readInt(all[_kLow], defLow),
      high: _readInt(all[_kHigh], defHigh),
      urgentHigh: _readInt(all[_kUrgentHigh], defUrgentHigh),
    );
  }
}
