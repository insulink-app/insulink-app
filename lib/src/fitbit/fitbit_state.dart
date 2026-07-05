import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'fitbit_importer.dart';
import 'fitbit_models.dart';

/// App-wide state for the Fitbit integration: whether it is "connected" (Health
/// Connect read permission granted) and the cached metrics. Self-persists to
/// secure storage (like the Profile*State classes) so the flag and last values
/// survive a relaunch. Provided above the page tree so the Devices sub-page and
/// the Sport section observe the same value.
class FitbitState extends ChangeNotifier {
  static const _kConnected = 'fitbit.connected';
  static const _kData = 'fitbit.data';
  static const _storage = FlutterSecureStorage();

  bool _connected;
  bool _busy = false;
  List<FitbitDay> _archive;
  int? _latestHr;
  int? _latestHrAtMs;

  FitbitState(
    this._connected,
    this._archive,
    this._latestHr,
    this._latestHrAtMs,
  );

  bool get connected => _connected;
  bool get busy => _busy;
  List<FitbitDay> get archive => _archive;
  int? get latestHr => _latestHr;
  int? get todayRestingHr => _latestOf((day) => day.restingHr);
  int? get lastSleepMinutes => _latestOf((day) => day.sleepMinutes);
  int? get latestSpo2 => _latestOf((day) => day.spo2);

  int? _latestOf(int? Function(FitbitDay) pick) {
    for (final day in _archive.reversed) {
      final value = pick(day);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// Grants Health Connect access + pulls the metrics; only marks connected on
  /// success (so a denied/unavailable result leaves the app unchanged).
  Future<FitbitImportResult> connect() async {
    final data = await _run();
    if (data.result == FitbitImportResult.success) {
      _connected = true;
      await _persist();
    }
    return data.result;
  }

  Future<void> disconnect() async {
    _connected = false;
    await _storage.write(key: _kConnected, value: 'false');
    notifyListeners();
  }

  /// Re-reads the metrics when connected (Health Connect isn't push, so the
  /// Sport page refreshes on open). No-op otherwise.
  Future<void> refreshIfConnected() async {
    if (!_connected) {
      return;
    }
    final data = await _run();
    if (data.result == FitbitImportResult.success) {
      await _persist();
    }
  }

  Future<FitbitImport> _run() async {
    if (_busy) {
      return const FitbitImport(FitbitImportResult.success);
    }
    _busy = true;
    notifyListeners();
    final data = await FitbitImporter().import();
    if (data.result == FitbitImportResult.success) {
      _merge(data);
    }
    _busy = false;
    notifyListeners();
    return data;
  }

  void _merge(FitbitImport data) {
    final byKey = {for (final day in _archive) day.dateKey: day};
    for (final day in data.days) {
      byKey[day.dateKey] = day;
    }
    _archive = byKey.values.toList()
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    if (data.latestHr != null) {
      _latestHr = data.latestHr;
      _latestHrAtMs = data.latestHrAtMs;
    }
  }

  Future<void> _persist() async {
    await _storage.write(key: _kConnected, value: '$_connected');
    await _storage.write(
      key: _kData,
      value: jsonEncode({
        'days': [for (final day in _archive) day.toJson()],
        'hr': _latestHr,
        'hrAt': _latestHrAtMs,
      }),
    );
  }

  static Future<FitbitState> load() async {
    final connected = (await _storage.read(key: _kConnected)) == 'true';
    final raw = await _storage.read(key: _kData);
    var archive = <FitbitDay>[];
    int? latestHr;
    int? latestHrAtMs;
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      archive = [
        for (final day in map['days'] as List)
          FitbitDay.fromJson(day as Map<String, dynamic>),
      ];
      latestHr = map['hr'] as int?;
      latestHrAtMs = map['hrAt'] as int?;
    }
    return FitbitState(connected, archive, latestHr, latestHrAtMs);
  }
}
