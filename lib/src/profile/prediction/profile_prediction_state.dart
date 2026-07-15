import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Glucose-prediction setting: whether the forecast overlay is shown, whether it
/// draws its uncertainty band, and the horizon (30 or 60 min). Persisted in
/// secure storage and mirrored to the account (see `ProfileSettings.collect`).
///
/// Provided above the page tree (see `main.dart`) so the profile widgets and the
/// [CgmController] observe the same value. The controller reads it fresh via
/// [load] each time it fetches, so a change takes effect without a restart.
class ProfilePredictionState extends ChangeNotifier {
  static const _kEnabled = 'prediction_enabled';
  static const _kBand = 'prediction_band';
  static const _kHorizon = 'prediction_horizon';
  static const _storage = FlutterSecureStorage();

  bool _enabled;
  bool _band;
  int _horizon;

  ProfilePredictionState(this._enabled, this._band, this._horizon);

  bool get enabled => _enabled;

  /// Draw the forecast as a band (q10–q90) instead of a bare mean line. Off by
  /// default: the band is honest but wide at long horizons, so it is opt-in.
  bool get band => _band;

  int get horizon => _horizon;

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) {
      return;
    }
    _enabled = value;
    notifyListeners();
    await _storage.write(key: _kEnabled, value: '$value');
  }

  Future<void> setBand(bool value) async {
    if (value == _band) {
      return;
    }
    _band = value;
    notifyListeners();
    await _storage.write(key: _kBand, value: '$value');
  }

  Future<void> setHorizon(int minutes) async {
    if (minutes == _horizon) {
      return;
    }
    _horizon = minutes;
    notifyListeners();
    await _storage.write(key: _kHorizon, value: '$minutes');
  }

  /// Read the persisted setting (30 unless a valid 60 is stored).
  static Future<ProfilePredictionState> load() async {
    final enabled = (await _storage.read(key: _kEnabled)) == 'true';
    final band = (await _storage.read(key: _kBand)) == 'true';
    final horizon = int.tryParse(await _storage.read(key: _kHorizon) ?? '');
    return ProfilePredictionState(enabled, band, horizon == 60 ? 60 : 30);
  }
}
