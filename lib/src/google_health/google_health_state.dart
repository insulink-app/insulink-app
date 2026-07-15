import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'fitbit_heart_rate_monitor.dart';
import 'google_health_importer.dart';
import 'google_health_models.dart';
import 'google_health_sync.dart';
import 'health_permissions.dart';
import 'intraday_pulse_store.dart';
import 'pulse_sync.dart';

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

  /// Full-metrics (incl. sleep) re-read cadence while the Sport page is open —
  /// Health Connect isn't push, so without this the daily metrics only refresh
  /// on page open and go stale on a long-open page.
  static const _metricsEvery = Duration(minutes: 5);

  /// How recently the band must have delivered for its bpm to count as live and
  /// be relayed. A few beats' grace over the band's ~1 Hz, so a short BLE hiccup
  /// does not blink the panel's reading out.
  static const _liveRelayMaxAge = Duration(seconds: 5);

  bool _connected;
  bool _busy = false;
  List<GoogleHealthDay> _archive;
  int? _latestHr;
  int? _latestHrAtMs;
  Timer? _liveTimer;
  Timer? _metricsTimer;

  /// Direct-BLE live pulse (a worn Fitbit), started with the Sport page. Its
  /// ~1 Hz samples are far fresher than Health Connect's slow sync, so they win
  /// [_applyLiveHr]'s newest-timestamp dedup while it streams.
  final FitbitHeartRateMonitor _bleMonitor = FitbitHeartRateMonitor();

  /// Granular intraday pulse archive + its backend sync. The live BLE samples
  /// are flushed here once a minute so the curve is persisted and mirrored to
  /// the account (not just held in the monitor's in-memory buffer).
  static const _pulseStore = IntradayPulseStore();
  DateTime? _lastPulseFlush;

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
    // Live BLE pulse runs app-wide (not page-scoped) so the heart-rate tile on
    // the overview / sport page shows + animates the real-time value.
    _bleMonitor.addListener(_onBleHr);
    _bleMonitor.start();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _metricsTimer?.cancel();
    _bleMonitor.dispose();
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
    _metricsTimer?.cancel();
    _liveTimer = Timer.periodic(_liveHrEvery, (_) => _pollLiveHr());
    _metricsTimer = Timer.periodic(_metricsEvery, (_) => refreshIfConnected());
    _pollLiveHr();
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _metricsTimer?.cancel();
    _metricsTimer = null;
  }

  /// Adopts the live BLE sample into [latestHr] and rebuilds observers on every
  /// monitor change (bpm AND status) so the tile's pulse tracks the live/idle
  /// state, not just fresh values.
  void _onBleHr() {
    _applyLiveHr(
      _bleMonitor.bpm,
      _bleMonitor.lastUpdate?.millisecondsSinceEpoch,
    );
    notifyListeners();
    _relayLivePulse();
    unawaited(_flushLivePulse());
  }

  /// Relays the current bpm to the account so the user's other devices (the web
  /// panel's workout vitals bar) can show it a second later.
  ///
  /// Only a genuinely fresh reading is relayed: [_onBleHr] also fires on status
  /// changes, and re-sending the last bpm then would keep refreshing the
  /// server's cache with a value the band never delivered — a disconnected band
  /// would look live on the panel forever. Going quiet is the signal that lets
  /// the cache expire.
  void _relayLivePulse() {
    final bpm = _bleMonitor.bpm;
    final at = _bleMonitor.lastUpdate;
    if (bpm == null || at == null) {
      return;
    }
    if (DateTime.now().difference(at) > _liveRelayMaxAge) {
      return;
    }
    PulseSync().pushLive(bpm);
  }

  /// Persists + syncs the live BLE samples buffered since the last flush, at
  /// most once a minute (the pulse store buckets to one point per minute, so
  /// flushing faster only rewrites today's blob for no extra resolution).
  Future<void> _flushLivePulse() async {
    final now = DateTime.now();
    final cutoff = _lastPulseFlush;
    if (cutoff != null && now.difference(cutoff).inSeconds < 60) {
      return;
    }
    _lastPulseFlush = now;
    final recent = [
      for (final sample in _bleMonitor.liveHistory)
        if (cutoff == null || sample.at.isAfter(cutoff)) sample,
    ];
    if (recent.isEmpty) {
      return;
    }
    final touched = await _pulseStore.merge(recent);
    PulseSync().push(touched);
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

  /// The live-BLE Fitbit reader (streams while [startLive] is active). Exposed so
  /// a page can show its real-time bpm + status directly.
  FitbitHeartRateMonitor get liveHrMonitor => _bleMonitor;

  bool get connected => _connected;
  bool get busy => _busy;
  List<GoogleHealthDay> get archive => _archive;
  int? get latestHr => _latestHr;
  int? get todayRestingHr => _latestOf((day) => day.restingHr);
  int? get lastSleepMinutes => _latestOf((day) => day.sleepMinutes);
  int? get latestSpo2 => _latestOf((day) => day.spo2);
  int? get latestRespiratoryRate => _latestOf((day) => day.respiratoryRate);

  int? _latestOf(int? Function(GoogleHealthDay) pick) {
    for (final day in _archive.reversed) {
      final value = pick(day);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// Why the last [connect] did not go through, or null after a success.
  ///
  /// Kept here rather than reported as a one-off event because it is not one: a
  /// denied permission or a missing Health Connect is a STANDING condition of
  /// the integration, true until the user changes something in the system
  /// settings. The status box renders it in place of its generic hint.
  GoogleHealthImportResult? get connectFailure => _connectFailure;
  GoogleHealthImportResult? _connectFailure;

  /// Grants Health Connect access + pulls the metrics; only marks connected on
  /// success (so a denied/unavailable result leaves the app unchanged).
  ///
  /// This is where the user asked to be asked: the prompt covers EVERY type the
  /// app reads, including the Sport page's steps/distance/calories/weight, so
  /// nothing pops up later on. The import right after reports the outcome.
  Future<GoogleHealthImportResult> connect() async {
    await HealthPermissions().request();
    final data = await _run();
    final ok = data.result == GoogleHealthImportResult.success;
    if (ok) {
      _connected = true;
      await _persist();
    }
    _connectFailure = ok ? null : data.result;
    notifyListeners();
    return data.result;
  }

  Future<void> disconnect() async {
    _connected = false;
    _connectFailure = null;
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
      GoogleHealthSync().push(_archive);
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

  /// Merges backend-pulled days into the persisted archive (on sign-in), keeping
  /// the connected flag and latest HR, and any local-only days. The provider
  /// reads this on its next [load]. Static because the pull runs before/without a
  /// provider handle (like the other sign-in sync pulls).
  static Future<void> mergePersisted(List<GoogleHealthDay> days) async {
    if (days.isEmpty) {
      return;
    }
    final raw = await _storage.read(key: _kData);
    final map = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final byKey = {
      for (final day in (map['days'] as List? ?? []))
        (day as Map)['d'] as String: day,
    };
    for (final day in days) {
      byKey[day.dateKey] = day.toJson();
    }
    map['days'] = (byKey.values.toList())
      ..sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));
    await _storage.write(key: _kData, value: jsonEncode(map));
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
