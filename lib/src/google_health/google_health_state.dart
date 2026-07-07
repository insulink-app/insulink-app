import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'google_health_importer.dart';
import 'google_health_models.dart';

/// App-wide state for the Google Health integration: whether it is "connected" (Health
/// Connect read permission granted) and the cached metrics. Self-persists to
/// secure storage (like the Profile*State classes) so the flag and last values
/// survive a relaunch. Provided above the page tree so the Devices sub-page and
/// the Sport section observe the same value.
class GoogleHealthState extends ChangeNotifier {
  static const _kConnected = 'google_health.connected';
  static const _kData = 'google_health.data';
  static const _storage = FlutterSecureStorage();

  /// Foreground live-HR poll cadence (mirrors the service-isolate cadence). Kept
  /// modest — Google Health syncs into Health Connect slowly, so faster only burns battery.
  static const _liveHrEvery = Duration(seconds: 60);

  bool _connected;
  bool _busy = false;
  List<GoogleHealthDay> _archive;
  int? _latestHr;
  int? _latestHrAtMs;
  Timer? _liveTimer;

  GoogleHealthState(
    this._connected,
    this._archive,
    this._latestHr,
    this._latestHrAtMs,
  );

  /// Registers the callback that receives live-HR pushes from the
  /// foreground-service isolate (see cgm_service `_maybePollHeartRate`). Called
  /// once when the provider is created (analog to `CgmController.init`).
  void init() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  void _onTaskData(Object data) {
    if (data is! Map || data['t'] != 'hr') {
      return;
    }
    _applyLiveHr(data['v'] as int?, data['at'] as int?);
  }

  /// Foreground poll for while the Sport page is open — covers the case where
  /// the CGM foreground service (the background HR host) isn't running. Both
  /// paths feed [_applyLiveHr], deduplicated by timestamp.
  void startLive() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(_liveHrEvery, (_) => _pollLiveHr());
    _pollLiveHr();
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  Future<void> _pollLiveHr() async {
    if (!_connected) {
      return;
    }
    final latest = await GoogleHealthImporter().latestHeartRate();
    _applyLiveHr(latest.hr, latest.atMs);
  }

  /// Adopts a fresh HR sample only if it is newer than the current one, then
  /// persists + notifies so the `bpm` tile updates live.
  void _applyLiveHr(int? hr, int? atMs) {
    if (hr == null || atMs == null) {
      return;
    }
    if (_latestHrAtMs != null && atMs <= _latestHrAtMs!) {
      return;
    }
    _latestHr = hr;
    _latestHrAtMs = atMs;
    notifyListeners();
    unawaited(_persist());
  }

  bool get connected => _connected;
  bool get busy => _busy;
  List<GoogleHealthDay> get archive => _archive;
  int? get latestHr => _latestHr;
  int? get todayRestingHr => _latestOf((day) => day.restingHr);
  int? get lastSleepMinutes => _latestOf((day) => day.sleepMinutes);
  int? get latestSpo2 => _latestOf((day) => day.spo2);

  int? _latestOf(int? Function(GoogleHealthDay) pick) {
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
  Future<GoogleHealthImportResult> connect() async {
    final data = await _run();
    if (data.result == GoogleHealthImportResult.success) {
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
    if (data.result == GoogleHealthImportResult.success) {
      await _persist();
    }
  }

  Future<GoogleHealthImport> _run() async {
    if (_busy) {
      return const GoogleHealthImport(GoogleHealthImportResult.success);
    }
    _busy = true;
    notifyListeners();
    final data = await GoogleHealthImporter().import();
    if (data.result == GoogleHealthImportResult.success) {
      _merge(data);
    }
    _busy = false;
    notifyListeners();
    return data;
  }

  void _merge(GoogleHealthImport data) {
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

  static Future<GoogleHealthState> load() async {
    final connected = (await _storage.read(key: _kConnected)) == 'true';
    final raw = await _storage.read(key: _kData);
    var archive = <GoogleHealthDay>[];
    int? latestHr;
    int? latestHrAtMs;
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      archive = [
        for (final day in map['days'] as List)
          GoogleHealthDay.fromJson(day as Map<String, dynamic>),
      ];
      latestHr = map['hr'] as int?;
      latestHrAtMs = map['hrAt'] as int?;
    }
    return GoogleHealthState(connected, archive, latestHr, latestHrAtMs);
  }
}
