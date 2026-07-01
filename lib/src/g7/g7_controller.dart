import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/g7/service/alarms.dart';
import 'package:insulink/src/g7/service/ble_service.dart';
import 'package:insulink/src/g7/service/service_log.dart';
import 'package:insulink/src/g7/protocol/device_info.dart';
import 'package:insulink/src/g7/protocol/glucose.dart';
import 'package:insulink/src/g7/event_sync.dart';
import 'package:insulink/src/g7/sensor_sync.dart';
import 'package:insulink/src/g7/store.dart';
import 'package:insulink/src/localization/service_strings.dart';
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

  /// Localized strings for the service notification (no [BuildContext] here).
  final ServiceStrings _strings = ServiceStrings();

  final List<String> _log = <String>[];
  List<String> get log => List.unmodifiable(_log);

  /// The same durable file the service isolate writes; read on launch so the
  /// log pane shows what the watchdog did while the app was closed.
  final ServiceLog _serviceLog = ServiceLog();

  bool _busy = false;
  bool get busy => _busy;

  /// True while the foreground service (which owns the BLE link) is running.
  bool _serviceRunning = false;
  bool get connected => _serviceRunning;

  /// Whether a sensor has been paired (cache key resolved), so it can be
  /// forgotten/stopped.
  bool get hasSensor => (_store?.resolvedKey ?? '').isNotEmpty;

  /// True once [init] has loaded the store. Until then we don't yet know whether
  /// a sensor is paired, so the UI should show a loader rather than the "no
  /// sensor" view (which briefly flashed on launch).
  bool get initialized => _store != null;

  G7Store? _store;

  /// glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  /// Mirrors what the background service persists to [G7Store]'s per-session
  /// cache. Kept only as the cold-launch fallback (before [_sensorStart] is
  /// known) and the source for [currentMgdl]/[_lastDataAt]; the overview chart
  /// reads [byTime] below, which is sourced from the durable archive instead.
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();

  /// Glucose history for the overview chart, keyed by seconds-since-session-
  /// start. Sourced from the DURABLE long-term archive (epoch-minute keyed,
  /// append-only, never capped or wiped within the 90-day retention), converted
  /// back to session-relative seconds via [_sensorStart].
  ///
  /// Deliberately NOT the per-session [G7Store.loadReadings] cache: that cache
  /// is capped (~300 pts), cleared on a new session, and reload-clobbered — which
  /// is exactly how points that were once on the chart disappeared. The archive
  /// keeps every point ever seen, so a value plotted once stays plotted until it
  /// slides out of the chart's own time window. Bounded to the last 24 h (the
  /// widest window the chart offers) so we never build more than a day of points;
  /// before a session start is known, falls back to the cached [_byTime].
  SplayTreeMap<int, int> get byTime {
    final store = _store;
    final start = _sensorStart;
    if (store == null || start == null) {
      return _byTime;
    }
    final startSecs = start.millisecondsSinceEpoch ~/ 1000;
    final now = DateTime.now();
    final dayAgo = now.subtract(const Duration(hours: 24));
    final out = SplayTreeMap<int, int>();
    store.archiveRange(start.isAfter(dayAgo) ? start : dayAgo, now).forEach((
      epochMin,
      mgdl,
    ) {
      final secs = epochMin * 60 - startSecs;
      if (secs >= 0) {
        out[secs] = mgdl;
      }
    });
    // Migration / cold-start safety: if the archive hasn't been populated yet
    // (e.g. right after this build, before the first EGV republishes the session
    // into it), fall back to the cached session points so the chart isn't empty.
    if (out.isEmpty) {
      return _byTime;
    }
    // Overlay the freshest live reading: the service archives it slightly after
    // the 'reading' ping, so the archive snapshot can briefly lag the newest
    // point. Minute-aligned to match (and dedupe against) the archived copy.
    final live = _latest;
    if (_latestIsLive && live?.glucoseMgDl != null) {
      final liveMin =
          start
              .add(Duration(seconds: live!.secsSinceStart))
              .millisecondsSinceEpoch ~/
          60000;
      out[liveMin * 60 - startSecs] = live.glucoseMgDl!;
    }
    return out;
  }

  /// Default analysis window for the statistics page.
  static const statsWindow = Duration(days: 7);

  /// Currently selected statistics window. A preset duration ([statsPreset],
  /// relative to now so it stays fresh) OR an explicit custom range
  /// ([statsCustomFrom]/[statsCustomTo]); the custom range wins when set.
  Duration _statsPreset = statsWindow;
  DateTime? _statsCustomFrom;
  DateTime? _statsCustomTo;

  Duration get statsPreset => _statsPreset;
  DateTime? get statsCustomFrom => _statsCustomFrom;
  DateTime? get statsCustomTo => _statsCustomTo;
  bool get statsIsCustom => _statsCustomFrom != null;

  set statsPreset(Duration window) {
    _statsPreset = window;
    _statsCustomFrom = null;
    _statsCustomTo = null;
    notifyListeners();
  }

  void setStatsCustomRange(DateTime from, DateTime to) {
    _statsCustomFrom = from;
    _statsCustomTo = to;
    notifyListeners();
  }

  /// The archive over the currently selected statistics window — the single
  /// source the statistics views read so the range selector drives them all.
  SplayTreeMap<int, int> get statsArchive {
    final from = _statsCustomFrom;
    final to = _statsCustomTo;
    if (from != null && to != null) {
      final store = _store;
      if (store == null) {
        return SplayTreeMap<int, int>();
      }
      return store.archiveRange(from, to);
    }
    return archiveSince(_statsPreset);
  }

  /// The effective length of the currently selected statistics window — the
  /// custom range's span when set, else the preset duration. Drives the history
  /// page's adaptive X-axis (hours vs days vs months).
  Duration get statsSpan {
    final from = _statsCustomFrom;
    final to = _statsCustomTo;
    if (from != null && to != null) {
      return to.difference(from);
    }
    return _statsPreset;
  }

  /// Logged events (lows/highs, signal loss, sensor swap/stop) over the currently
  /// selected statistics window, newest first — drives the events page.
  List<({DateTime time, String type, int? value})> get statsEvents {
    final store = _store;
    if (store == null) {
      return [];
    }
    final from = _statsCustomFrom;
    final to = _statsCustomTo;
    if (from != null && to != null) {
      return store.eventsBetween(from, to);
    }
    final now = DateTime.now();
    return store.eventsBetween(now.subtract(_statsPreset), now);
  }

  /// Long-term glucose history over the last [window], keyed by epoch-minute
  /// (recover wall-clock time via `DateTime.fromMillisecondsSinceEpoch(min *
  /// 60000)`). Unlike [byTime] this spans sensor swaps, stops and reconnects —
  /// it's the absolute-time archive the background service appends to, and the
  /// basis for the statistics views. Reads the store cache the controller keeps
  /// fresh via [reload] on every `update` ping and on resume.
  SplayTreeMap<int, int> archiveSince(Duration window) {
    final store = _store;
    if (store == null) {
      return SplayTreeMap<int, int>();
    }
    final now = DateTime.now();
    return store.archiveRange(now.subtract(window), now);
  }

  /// Builds a reading from a persisted/IPC map. The trend field is keyed
  /// differently by the cached headline ('trend') and the live service payload
  /// ('trendTenths'); the other fixed fields aren't carried across.
  G7GlucoseReading _reading(Map map, String trendKey) {
    return G7GlucoseReading(
      secsSinceStart: map['secs'] as int? ?? 0,
      age: 0,
      sequence: 0,
      glucoseMgDl: map['mgdl'] as int?,
      predictedMgDl: 0,
      trendTenths: map[trendKey] as int? ?? 0,
      state: map['state'] as int? ?? 0,
    );
  }

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
    final reading = _latest;
    if (reading == null) {
      return null;
    }
    final start = _sensorStart;
    if (start != null) {
      return start.add(Duration(seconds: reading.secsSinceStart));
    }
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
    final store = await G7Store.open();
    if (_disposed) {
      return;
    }
    _store = store;
    code.text = store.pairingCode ?? '';
    await _seedLogFromFile();
    _restoreFromCache(store);
    notifyListeners();
    if (_byTime.isNotEmpty) {
      _append('showing ${_byTime.length} cached readings');
    }
    await _refreshServiceState();
    // Start the read pipeline if it's down, or revive a frozen one that claims
    // to run but produced no data (see _recoverIfStale).
    await _recoverIfStale();
  }

  /// Populates the live reading, history, device info and sensor start from the
  /// store cache so the UI shows something immediately, before the service
  /// produces a fresh reading. The headline value stays marked non-live until
  /// one arrives. Data is keyed by the resolved key (the sensor BLE id).
  void _restoreFromCache(G7Store store) {
    final key = _key;
    if (key.isEmpty) {
      return;
    }
    _byTime.addAll(store.loadReadings(key));
    _info = store.loadInfo(key) ?? _info;
    _sensorStart = store.loadSensorStart(key);
    final latest = store.loadLatest(key);
    if (latest != null) {
      _latest = _reading(latest, 'trend');
      _latestIsLive = false;
    }
  }

  /// Staleness threshold. The G7 delivers roughly every 5 min, so no fresh
  /// reading for well over two cycles means the background link is dead — Doze,
  /// a killed/frozen service isolate, or a stuck scan — and the service must be
  /// revived. `isRunningService` alone can read "running" while the hosting
  /// isolate is frozen, which is why time-since-data is the real signal.
  static const _staleAfter = Duration(minutes: 12);

  /// Minimum spacing between service restarts. `restartService()` tears down the
  /// isolate and starts a FRESH BLE scan; a scan+connect cycle can take up to
  /// ~2 min (the 120 s scan timeout). Without a cooldown, repeated resumes while
  /// data is stale fire `restartService()` back-to-back, each aborting the
  /// in-flight scan and starting another — which trips Android's "scanning too
  /// frequently" throttle and then returns NO results for ~30 min (the multi-hour
  /// "0 devices found" stall). So skip a restart if we restarted recently and let
  /// the running scan finish.
  static const _restartCooldown = Duration(minutes: 3);
  DateTime? _lastRestartAt;

  /// Wall-clock time of the newest data we know about — the live/cached headline
  /// reading OR the newest history point, whichever is later. Used to decide
  /// whether the background service has actually stalled.
  DateTime? get _lastDataAt {
    final byLatest = lastUpdate;
    final start = _sensorStart;
    final byHistory = (start != null && _byTime.isNotEmpty)
        ? start.add(Duration(seconds: _byTime.lastKey()!))
        : null;
    if (byLatest == null) {
      return byHistory;
    }
    if (byHistory == null) {
      return byLatest;
    }
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
    if (key.isEmpty || _store?.sessionKey(key) == null) {
      return;
    }
    final running = await FlutterForegroundTask.isRunningService;
    if (_disposed) {
      return;
    }
    if (!running) {
      _append('auto-connecting…');
      await start();
      return;
    }
    final last = _lastDataAt;
    final stale = last == null || DateTime.now().difference(last) > _staleAfter;
    if (!stale) {
      return;
    }
    // Throttle restarts: a fresh service needs up to ~2 min to scan+connect, so
    // restarting again before then just aborts its in-flight scan and churns
    // startScan calls into Android's scan throttle (see _restartCooldown).
    final lastRestart = _lastRestartAt;
    if (lastRestart != null &&
        DateTime.now().difference(lastRestart) < _restartCooldown) {
      return;
    }
    _lastRestartAt = DateTime.now();
    _append('no fresh data — restarting background service');
    await FlutterForegroundTask.restartService();
    if (_disposed) {
      return;
    }
    await _refreshServiceState();
  }

  /// The key cached data is stored under: the resolved key set by the read
  /// pipeline, falling back to the user serial (covers the brief window before
  /// the pipeline has resolved one).
  String get _key => _store?.resolvedKey ?? _store?.serial ?? '';

  void _append(String line) {
    if (_disposed) {
      return;
    }
    _log.insert(0, line);
    notifyListeners();
  }

  /// Load the durable service log (oldest-first on disk) into [_log] (newest-
  /// first in memory) so the pane shows overnight watchdog activity on launch.
  Future<void> _seedLogFromFile() async {
    final history = await _serviceLog.readAll();
    if (history.trim().isEmpty || _disposed) {
      return;
    }
    _log.addAll(history.trimRight().split('\n').reversed);
  }

  /// Messages from the background service: log lines, the latest live reading,
  /// a "reload from store" ping, and connection-state transitions.
  void _onTaskData(Object data) {
    if (data is! Map) {
      return;
    }
    switch (data['t']) {
      case 'log':
        _append(data['line'] as String? ?? '');
      case 'reading':
        if (_disposed) {
          return;
        }
        _latest = _reading(data, 'trendTenths');
        _latestIsLive = true;
        _latestAt = DateTime.now();
        // Plot the live point immediately. The chart otherwise waits for the
        // 'update' store reload, which races the unawaited persist in the
        // service isolate and drops the newest point for a cycle.
        final mgdl = data['mgdl'] as int?;
        final secs = data['secs'] as int?;
        if (mgdl != null && secs != null) {
          _byTime[secs] = mgdl;
        }
        notifyListeners();
      case 'update':
        _reloadFromStore();
    }
  }

  /// Re-read everything the service persisted (history, info, sensor start).
  /// Requires reloading the store's in-memory cache since the writes happened
  /// in the service isolate.
  Future<void> _reloadFromStore() async {
    final store = _store;
    if (store == null) {
      return;
    }
    await store.reload();
    // Use the resolved key (the service may have just set it after pairing with
    // a blank serial), not the text field.
    final key = _key;
    if (key.isEmpty || _disposed) {
      return;
    }
    _byTime
      ..clear()
      ..addAll(store.loadReadings(key));
    // Keep the live point the 'reading' ping already plotted: the store write
    // in the service isolate may not have flushed yet, so reloading from it
    // would briefly drop the newest point and make the chart flicker.
    final live = _latest;
    if (_latestIsLive && live?.glucoseMgDl != null) {
      _byTime[live!.secsSinceStart] = live.glucoseMgDl!;
    }
    _info = store.loadInfo(key) ?? _info;
    _sensorStart = store.loadSensorStart(key) ?? _sensorStart;
    notifyListeners();
  }

  Future<void> _refreshServiceState() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (_disposed) {
      return;
    }
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
        // Keep the Wi-Fi radio up while the service runs. With the screen off in
        // Doze, Android powers the radio down even though the wake lock keeps the
        // CPU alive — so the glucose-report POST fails DNS ("Failed host lookup /
        // No address associated with hostname", errno=7) and readings never reach
        // the backend. A Wi-Fi lock holds the radio in a connected state so the
        // background requests go through screen-off, the way the Dexcom app does.
        allowWifiLock: true,
      ),
    );
  }

  /// Start the foreground service that connects and streams glucose. The BLE
  /// work lives in that service isolate, so it survives the app being
  /// backgrounded or closed.
  Future<void> start() async {
    if (_busy) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      if (!await _requestPermissions()) {
        _append('Bluetooth permission denied — cannot start');
        return;
      }
      // The service isolate reads the pairing code from the store on start; the
      // serial stays blank and is resolved to the sensor BLE id by the pipeline.
      await _store?.saveIdentity(serial: '', pairingCode: code.text.trim());
      _initForegroundTask();
      await _startService();
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

  /// Acquires everything the background service needs before it starts: BLE
  /// runtime permissions (a `connectedDevice` FGS on Android 14+ validates the
  /// app holds one, and the scan runs in the dialog-less service isolate),
  /// notification permission, DnD bypass for alarms (must be granted in the UI
  /// BEFORE the service isolate creates the bypassDnd channels) and a
  /// battery-optimization exemption. Returns false only when BLE is denied — the
  /// hard blocker.
  Future<bool> _requestPermissions() async {
    if (!await _ensureBlePermissions()) {
      return false;
    }
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    await G7AlarmManager(FlutterLocalNotificationsPlugin()).ensureDndAccess();
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    return true;
  }

  /// The account's stored sensor to offer for restore, or null when there's
  /// already a local sensor, none on the backend, or the offer was dismissed.
  Future<SensorRestore?> availableBackendSensor(BuildContext context) async {
    if (hasSensor) {
      return null;
    }
    final restore = await SensorSync().fetchCurrent(context);
    if (restore == null) {
      return null;
    }
    if (_store?.restoreDismissedId == restore.sensorId) {
      return null;
    }
    return restore;
  }

  /// Remember the user declined restoring [sensorId] so it isn't offered again.
  Future<void> dismissRestore(String sensorId) async {
    await _store?.setRestoreDismissed(sensorId);
  }

  /// Adopt the sensor the backend has on file (offered on a fresh install when
  /// no sensor is set up locally): restore its identity into the store so the
  /// pipeline can reconnect without re-pairing, then start reading.
  Future<void> restoreSensor(SensorRestore restore) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await store.saveIdentity(serial: '', pairingCode: restore.pairingCode);
    await store.saveResolvedKey(restore.resolvedKey);
    await store.saveDeviceId(restore.resolvedKey, restore.deviceId);
    await store.saveSessionKeyHex(restore.resolvedKey, restore.sessionKeyHex);
    await store.saveBackendSensorId(restore.resolvedKey, restore.sensorId);
    final infoJson = restore.infoJson;
    if (infoJson != null) {
      final start = restore.sensorStartMs;
      await store.saveInfo(
        restore.resolvedKey,
        G7DeviceInfo.fromJson(infoJson),
        start == null ? null : DateTime.fromMillisecondsSinceEpoch(start),
      );
    }
    code.text = restore.pairingCode;
    _restoreFromCache(store);
    notifyListeners();
    await start();
  }

  Future<void> _startService() async {
    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      serviceTypes: await _serviceTypes(),
      notificationTitle: 'Insulink',
      notificationText: await _strings.get('service.connecting'),
      callback: startCallback,
    );
    if (result is ServiceRequestSuccess) {
      _append('background service started');
    } else if (result is ServiceRequestFailure) {
      _append('service start failed: ${result.error}');
    }
  }

  /// Service types for the foreground service. `location` is added ONLY when the
  /// OS location permission is held — the location FGS type requires it at
  /// `startForeground` (Android 14+), and glucose reading must never depend on
  /// location. With the type present the service samples GPS in the background
  /// (see [BackgroundLocationSampler]); without it, only glucose runs.
  Future<List<ForegroundServiceTypes>> _serviceTypes() async {
    final types = [ForegroundServiceTypes.connectedDevice];
    if (await Permission.location.isGranted) {
      types.add(ForegroundServiceTypes.location);
    }
    return types;
  }

  /// Fire a test alarm (low or high) so the user can preview the notification +
  /// tone from the settings UI. Runs in this UI isolate (its own alarm manager),
  /// ensuring notification + DnD access first, since the service isolate can't
  /// show those dialogs.
  Future<void> testAlarm({required bool high}) async {
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final alarms = G7AlarmManager(FlutterLocalNotificationsPlugin());
    await alarms.init();
    await alarms.ensureDndAccess();
    await alarms.fireTest(high: high);
  }

  Future<void> disconnect() async {
    await FlutterForegroundTask.stopService();
    _append('disconnected');
    if (_disposed) {
      return;
    }
    _serviceRunning = false;
    _latest = null;
    _latestIsLive = false;
    notifyListeners();
  }

  /// Forget the sensor: stop reading and wipe the stored session key + this
  /// sensor's session cache so the app no longer auto-reconnects. The physical
  /// sensor keeps running — this is an app-side unpair, not a sensor stop
  /// command. The long-term glucose archive ([archiveSince]) is KEPT, so the
  /// statistics survive switching to a new sensor; only the current-session
  /// chart resets. With the session key cleared, the next connect scans broadly
  /// and pairs whatever new sensor is presented (see G7Connection.connect).
  Future<void> forgetSensor() async {
    final key = _key;
    await FlutterForegroundTask.stopService();
    await _store?.addEvent('sensor_stopped');
    final store = _store;
    if (store != null) {
      await EventSync().sync(store, _append);
    }
    await _store?.clearSensor(key);
    _append('sensor forgotten');
    if (_disposed) {
      return;
    }
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
