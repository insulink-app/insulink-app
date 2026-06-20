import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:insulink/src/g7/ble_service.dart';
import 'package:insulink/src/g7/device_info.dart';
import 'package:insulink/src/g7/glucose.dart';
import 'package:insulink/src/g7/store.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shared, UI-free state + control for the Dexcom G7 read pipeline.
///
/// Holds the live reading, glucose history, device info, log and service
/// state, and drives the foreground service that owns the BLE link. It's a
/// [ChangeNotifier] provided above the page tree so several pages (overview,
/// sensor) observe the same data. The actual BLE work lives in the
/// foreground-service isolate (see [ble_service.dart]); this class is the UI
/// isolate's viewer + remote control.
class G7Controller extends ChangeNotifier with WidgetsBindingObserver {
  /// Pairing-code input. Owned here so the connect form (overview) and the start
  /// logic stay in sync and survive page switches. (No serial input: the serial
  /// is only a cache key and is resolved automatically from the sensor's BLE id.)
  final code = TextEditingController();

  final List<String> _log = <String>[];
  List<String> get log => List.unmodifiable(_log);

  bool _busy = false;
  bool get busy => _busy;

  /// True while the foreground service (which owns the BLE link) is running.
  bool _serviceRunning = false;
  bool get connected => _serviceRunning;

  /// Whether a sensor has been paired (cache key resolved), so it can be
  /// forgotten/stopped.
  bool get hasSensor => (_store?.resolvedKey ?? '').isNotEmpty;

  G7Store? _store;

  /// glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  /// Mirrors what the background service persists to [G7Store].
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  SplayTreeMap<int, int> get byTime => _byTime;

  G7GlucoseReading? _latest;
  G7GlucoseReading? get latest => _latest;

  /// False when [_latest] was restored from cache (shown dimmed as "cached"),
  /// true once a live reading arrives from the service.
  bool _latestIsLive = false;
  bool get latestIsLive => _latestIsLive;

  /// Wall-clock time a live reading last arrived from the service. Fallback for
  /// the "last update" time when the sensor session start isn't known.
  DateTime? _latestAt;

  G7DeviceInfo _info = G7DeviceInfo();
  G7DeviceInfo get info => _info;

  DateTime? _sensorStart;
  DateTime? get sensorStart => _sensorStart;

  bool _disposed = false;

  /// Wall-clock time of the latest glucose reading. Derived from the sensor's own
  /// session clock (`sensorStart + secsSinceStart`) so it's correct even for the
  /// value restored from cache on launch; falls back to the live arrival time.
  DateTime? get lastUpdate {
    final l = _latest;
    if (l == null) return null;
    final start = _sensorStart;
    if (start != null) return start.add(Duration(seconds: l.secsSinceStart));
    return _latestAt;
  }

  /// Current glucose value to display: the live reading, else the last cached
  /// history point.
  int? get currentMgdl =>
      _latest?.glucoseMgDl ??
      (_byTime.isNotEmpty ? _byTime[_byTime.lastKey()] : null);

  /// The whole log oldest-line-first (chronological), for copying/sharing.
  /// [_log] is stored newest-first, so it's reversed here.
  String get logText => _log.reversed.join('\n');

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    // Receive live updates pushed from the foreground-service isolate.
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    final s = await G7Store.open();
    if (_disposed) return;
    _store = s;
    code.text = s.pairingCode ?? '';
    // Cached data is keyed by the resolved key (the sensor BLE id).
    final key = _key;
    // Show cached history, latest value + device info immediately.
    final cached = key.isEmpty ? <int, int>{} : s.loadReadings(key);
    final latest = key.isEmpty ? null : s.loadLatest(key);
    _byTime.addAll(cached);
    if (key.isNotEmpty) {
      _info = s.loadInfo(key) ?? _info;
      _sensorStart = s.loadSensorStart(key);
    }
    if (latest != null) {
      _latest = G7GlucoseReading(
        secsSinceStart: latest['secs'] as int? ?? 0,
        age: 0,
        sequence: 0,
        glucoseMgDl: latest['mgdl'] as int?,
        predictedMgDl: 0,
        trendTenths: latest['trend'] as int? ?? 0,
        state: latest['state'] as int? ?? 0,
      );
      _latestIsLive = false; // from cache until a live reading arrives
    }
    notifyListeners();
    if (cached.isNotEmpty) {
      _append('showing ${cached.length} cached readings');
    }
    await _refreshServiceState();
    // Start the read pipeline if it's down, or revive a frozen one that claims
    // to run but produced no data (see _recoverIfStale).
    await _recoverIfStale();
  }

  /// Staleness threshold. The G7 delivers roughly every 5 min, so no fresh
  /// reading for well over two cycles means the background link is dead — Doze,
  /// a killed/frozen service isolate, or a stuck scan — and the service must be
  /// revived. `isRunningService` alone can read "running" while the hosting
  /// isolate is frozen, which is why time-since-data is the real signal.
  static const _staleAfter = Duration(minutes: 12);

  /// Wall-clock time of the newest data we know about — the live/cached headline
  /// reading OR the newest history point, whichever is later. Used to decide
  /// whether the background service has actually stalled.
  DateTime? get _lastDataAt {
    final byLatest = lastUpdate;
    final start = _sensorStart;
    final byHistory = (start != null && _byTime.isNotEmpty)
        ? start.add(Duration(seconds: _byTime.lastKey()!))
        : null;
    if (byLatest == null) return byHistory;
    if (byHistory == null) return byLatest;
    return byLatest.isAfter(byHistory) ? byLatest : byHistory;
  }

  /// Revive reading when the app comes back (launch or resume): start the
  /// service if it isn't running, or restart it — fresh isolate + Rust core +
  /// BLE scan — if it claims to run but hasn't produced a reading within
  /// [_staleAfter]. Without this the UI trusts `isRunningService` and never
  /// recovers a frozen service: you'd reopen the app and still get nothing
  /// (the symptom behind this method; see CLAUDE.md background gotchas).
  Future<void> _recoverIfStale() async {
    final key = _key;
    if (key.isEmpty || _store?.sessionKey(key) == null) return;
    final running = await FlutterForegroundTask.isRunningService;
    if (_disposed) return;
    if (!running) {
      _append('auto-connecting…');
      await start();
      return;
    }
    final last = _lastDataAt;
    final stale = last == null || DateTime.now().difference(last) > _staleAfter;
    if (stale) {
      _append('no fresh data — restarting background service');
      await FlutterForegroundTask.restartService();
      if (_disposed) return;
      await _refreshServiceState();
    }
  }

  /// The key cached data is stored under: the resolved key set by the read
  /// pipeline, falling back to the user serial (covers the brief window before
  /// the pipeline has resolved one).
  String get _key => _store?.resolvedKey ?? _store?.serial ?? '';

  void _append(String s) {
    if (_disposed) return;
    _log.insert(0, s);
    notifyListeners();
  }

  /// Messages from the background service: log lines, the latest live reading,
  /// a "reload from store" ping, and connection-state transitions.
  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['t']) {
      case 'log':
        _append(data['line'] as String? ?? '');
      case 'reading':
        if (_disposed) return;
        _latest = G7GlucoseReading(
          secsSinceStart: data['secs'] as int? ?? 0,
          age: 0,
          sequence: 0,
          glucoseMgDl: data['mgdl'] as int?,
          predictedMgDl: 0,
          trendTenths: data['trendTenths'] as int? ?? 0,
          state: data['state'] as int? ?? 0,
        );
        _latestIsLive = true;
        _latestAt = DateTime.now();
        notifyListeners();
      case 'update':
        _reloadFromStore();
    }
  }

  /// Re-read everything the service persisted (history, info, sensor start).
  /// Requires reloading the store's in-memory cache since the writes happened
  /// in the service isolate.
  Future<void> _reloadFromStore() async {
    final s = _store;
    if (s == null) return;
    await s.reload();
    // Use the resolved key (the service may have just set it after pairing with
    // a blank serial), not the text field.
    final key = _key;
    if (key.isEmpty || _disposed) return;
    final cached = s.loadReadings(key);
    _byTime
      ..clear()
      ..addAll(cached);
    _info = s.loadInfo(key) ?? _info;
    _sensorStart = s.loadSensorStart(key) ?? _sensorStart;
    notifyListeners();
  }

  Future<void> _refreshServiceState() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (_disposed) return;
    _serviceRunning = running;
    notifyListeners();
  }

  /// Request the BLE permissions the background scan/connect needs. On
  /// Android 12+ these are `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`; on older
  /// versions scanning needs location instead (auto-granted scan/connect).
  Future<bool> _ensureBlePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    // Modern devices need scan+connect; pre-12 falls back to location.
    return (scanOk && connectOk) || locOk;
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'insulink',
        channelName: 'Dexcom G7 connection',
        channelDescription:
            'Keeps the glucose connection alive in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Watchdog tick that lets the handler reconnect after a drop.
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start the foreground service that connects and streams glucose. The BLE
  /// work lives in that service isolate, so it survives the app being
  /// backgrounded or closed.
  Future<void> start() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      // Bluetooth runtime permissions must be GRANTED before starting a
      // `connectedDevice` foreground service (Android 14+ validates the app
      // holds one), and because the scan now runs in the background isolate
      // which cannot show permission dialogs. Request them here in the UI.
      if (!await _ensureBlePermissions()) {
        _append('Bluetooth permission denied — cannot start');
        return;
      }
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // The service isolate reads the pairing code from the store on start; the
      // serial stays blank and is resolved to the sensor BLE id by the pipeline.
      await _store?.saveIdentity(serial: '', pairingCode: code.text.trim());

      _initForegroundTask();
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        serviceTypes: const [ForegroundServiceTypes.connectedDevice],
        notificationTitle: 'Dexcom G7',
        notificationText: 'connecting…',
        callback: startCallback,
      );
      if (result is ServiceRequestSuccess) {
        _append('background service started');
      } else if (result is ServiceRequestFailure) {
        _append('service start failed: ${result.error}');
      }
      await _refreshServiceState();
    } catch (e) {
      _append('ERROR: $e');
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> disconnect() async {
    await FlutterForegroundTask.stopService();
    _append('disconnected');
    if (_disposed) return;
    _serviceRunning = false;
    _latest = null;
    _latestIsLive = false;
    notifyListeners();
  }

  /// Forget the sensor: stop reading and wipe the stored session key + cache so
  /// the app no longer auto-reconnects. The physical sensor keeps running — this
  /// is an app-side unpair, not a sensor stop command.
  Future<void> forgetSensor() async {
    final key = _key;
    await FlutterForegroundTask.stopService();
    await _store?.clearSensor(key);
    _append('sensor forgotten');
    if (_disposed) return;
    _serviceRunning = false;
    _latest = null;
    _latestIsLive = false;
    _byTime.clear();
    _info = G7DeviceInfo();
    _sensorStart = null;
    code.text = '';
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  /// On resume: catch up on whatever the service persisted while we were away,
  /// then revive the service if it died or stalled in the background.
  Future<void> _onResumed() async {
    await _refreshServiceState();
    await _reloadFromStore();
    await _recoverIfStale();
  }

  @override
  void dispose() {
    _disposed = true;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.removeObserver(this);
    code.dispose();
    super.dispose();
  }
}
