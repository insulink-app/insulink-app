import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// NotificationVisibility is hidden here: both plugins define one, and the
// foreground service's notification is configured with the foreground-task
// package's version.
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:insulink/src/cgm/service/advisory_delivery.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/service/cgm_service.dart';
import 'package:insulink/src/libre3/libre3_activation.dart';
import 'package:insulink/src/cgm/protocol/device_info.dart';
import 'package:insulink/src/cgm/event_sync.dart';
import 'package:insulink/src/cgm/glucose_prediction.dart';
import 'package:insulink/src/cgm/sensor_sync.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/localization/service_strings.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/prediction/profile_prediction_state.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shared, UI-free state + control for the CGM read pipeline (Dexcom G7 or
/// FreeStyle Libre 3 — the active sensor is [CgmStore.sensorType]).
///
/// Holds the live reading, glucose history, device info, log and service
/// state, and drives the foreground service that owns the BLE link. It deals in
/// sensor-agnostic mg/dL / history / archive, so a single instance serves both
/// sensors. It's a
/// [ChangeNotifier] provided above the page tree so several pages (overview,
/// sensor) observe the same data. The actual BLE work lives in the
/// foreground-service isolate (see [cgm_service.dart]); this class is the UI
/// isolate's viewer + remote control.
class CgmController extends ChangeNotifier with WidgetsBindingObserver {
  /// Pairing-code input. Owned here so the connect form (overview) and the start
  /// logic stay in sync and survive page switches. (No serial input: the serial
  /// is only a cache key and is resolved automatically from the sensor's BLE id.)
  final code = TextEditingController();

  /// Localized strings for the service notification (no [BuildContext] here).
  final ServiceStrings _strings = ServiceStrings();

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

  /// The CGM the pairing UI + read pipeline should use. Defaults to the Dexcom
  /// G7 until a Libre 3 is activated (or the type is switched).
  SensorType get sensorType => _store?.sensorType ?? SensorType.dexcomG7;

  /// Switch the sensor type the pairing UI shows (persisted so the service
  /// isolate builds the matching connection).
  Future<void> setSensorType(SensorType type) async {
    await _store?.saveSensorType(type);
    notifyListeners();
  }

  /// Abort an in-progress [activateLibre3] NFC scan (user dismissed the sheet).
  Future<void> cancelLibre3Scan() => Libre3Activation.abort();

  /// Activate a FreeStyle Libre 3 over NFC and start reading it. Returns null on
  /// success, or a message describing why the scan failed. [accountId] is the
  /// LibreView GUID — needed only to take over a sensor Abbott's app already
  /// activated; leave blank for a fresh sensor.
  /// [onActivated] fires the moment the NFC read succeeds and is persisted —
  /// before the (slower, possibly permission-gated) [start] — so the UI can drop
  /// the "hold the sensor" prompt and show "connecting" while BLE comes up.
  Future<String?> activateLibre3({
    String accountId = '',
    void Function()? onActivated,
  }) async {
    final store = _store;
    if (store == null) {
      return 'not ready';
    }
    try {
      final result = await Libre3Activation(accountId: accountId).run();
      final key = result.bleMac;
      await store.saveSensorType(SensorType.abbottLibre3);
      await store.saveResolvedKey(key);
      await store.saveLibreMac(key, result.bleMac);
      await store.saveLibrePin(key, result.blePin);
      await store.clearLibreAuthKey(key);
      _append(
        'Libre 3 activated: ${result.bleMac} pin ${store.librePinHex(key)}',
      );
      await store.saveIdentity(serial: '', pairingCode: '');
      code.text = '';
      onActivated?.call();
      await start();
      return null;
    } catch (error) {
      _append('Libre 3 activation failed: $error');
      return '$error';
    }
  }

  /// True once [init] has loaded the store. Until then we don't yet know whether
  /// a sensor is paired, so the UI should show a loader rather than the "no
  /// sensor" view (which briefly flashed on launch).
  bool get initialized => _store != null;

  CgmStore? _store;

  /// glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  /// Mirrors what the background service persists to [CgmStore]'s per-session
  /// cache. Kept only as the cold-launch fallback (before [_sensorStart] is
  /// known) and the source for [currentMgdl]/[_lastDataAt]; the overview chart
  /// reads [byTime] below, which is sourced from the durable archive instead.
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();

  /// Glucose history for the overview chart, keyed by seconds-since-session-
  /// start. Sourced from the DURABLE long-term archive (epoch-minute keyed,
  /// append-only, never capped or wiped within the 90-day retention), converted
  /// back to session-relative seconds via [_sensorStart].
  ///
  /// Deliberately NOT the per-session [CgmStore.loadReadings] cache: that cache
  /// is capped (~300 pts), cleared on a new session, and reload-clobbered — which
  /// is exactly how points that were once on the chart disappeared. The archive
  /// keeps every point ever seen, so a value plotted once stays plotted until it
  /// slides out of the chart's own time window. Bounded to the last 24 h (the
  /// widest window the chart offers) so we never build more than a day of points;
  /// before a session start is known, falls back to the cached [_byTime].
  ///
  /// Spans sensor swaps ([includePreSession]): a fresh sensor's start is only
  /// minutes old, so clipping to it would drop the previous sensor's readings and
  /// leave the 24 h chart showing only the new session. Pre-session points are
  /// keyed by negative seconds and the chart plots them left of x=0, as
  /// [chartHistory] already does.
  SplayTreeMap<int, int> get byTime =>
      _byTimeWithin(const Duration(hours: 24), includePreSession: true);

  /// A cheap fingerprint of everything [byTime] plots. The overview gates the
  /// expensive fl_chart rebuild on this via a `Selector`, so the burst of
  /// service pings on open that notify WITHOUT touching the plotted data (log
  /// lines, connection-state, prediction) no longer re-lay-out the chart. It
  /// changes whenever a reading, the session start, or the live overlay changes.
  // ponytail: fingerprints the session cache (size + newest point) + session +
  // live overlay, NOT the archive `byTime` actually reads — an archive-only
  // change that leaves `_byTime` untouched (e.g. a pre-session point from a
  // sensor swap) is missed until the next reading ping refreshes it. Fold an
  // archive counter in if a stale preview is ever seen.
  int get chartRevision => Object.hash(
    _byTime.length,
    _byTime.isEmpty ? 0 : _byTime.lastKey(),
    _byTime.isEmpty ? 0 : _byTime[_byTime.lastKey()],
    _sensorStart?.millisecondsSinceEpoch,
    _latestIsLive,
    _latest?.glucoseMgDl,
  );

  /// Wider history for the full-screen chart's interval navigation (paging back
  /// through earlier days), same session-relative-seconds keying as [byTime].
  /// Includes archive data from BEFORE the current session start (keyed by
  /// negative seconds) so paging back crosses a sensor swap instead of stopping
  /// at the gap where the new session began.
  SplayTreeMap<int, int> get chartHistory =>
      _byTimeWithin(const Duration(days: 7), includePreSession: true);

  SplayTreeMap<int, int> _byTimeWithin(
    Duration lookback, {
    bool includePreSession = false,
  }) {
    final store = _store;
    if (store == null) {
      return _byTime;
    }
    final start = _sensorStart;
    if (start == null) {
      return _archiveByTimeNoSession(store);
    }
    final startSecs = start.millisecondsSinceEpoch ~/ 1000;
    final now = DateTime.now();
    final dayAgo = now.subtract(lookback);
    final from = (!includePreSession && start.isAfter(dayAgo)) ? start : dayAgo;
    final out = SplayTreeMap<int, int>();
    store.archiveRange(from, now).forEach((epochMin, mgdl) {
      final secs = epochMin * 60 - startSecs;
      if (includePreSession || secs >= 0) {
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

  /// Chart series when no current session start is known yet — e.g. a returning
  /// device right after sign-in, whose glucose came from [GlucoseSync.pullHistory]
  /// into the archive but which hasn't connected a sensor. Plots the last 24 h of
  /// the archive keyed by seconds relative to its OLDEST point (a self-consistent
  /// origin the chart can render without a session clock), so the overview shows
  /// the synced history — with the headline value pending as a loader — instead
  /// of the full "searching" screen. Falls back to the cached session points when
  /// the archive is empty.
  SplayTreeMap<int, int> _archiveByTimeNoSession(CgmStore store) {
    final now = DateTime.now();
    final archive = store.archiveRange(
      now.subtract(const Duration(hours: 24)),
      now,
    );
    if (archive.isEmpty) {
      return _byTime;
    }
    final firstMin = archive.firstKey()!;
    final out = SplayTreeMap<int, int>();
    archive.forEach((epochMin, mgdl) {
      out[(epochMin - firstMin) * 60] = mgdl;
    });
    return out;
  }

  /// Default analysis window for the analysis page.
  static const statsWindow = Duration(days: 7);

  /// Currently selected analysis window. A preset duration ([statsPreset],
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

  /// The archive over the currently selected analysis window — the single
  /// source the analysis views read so the range selector drives them all.
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

  /// The currently selected analysis window as an absolute range. The archive
  /// getters resolve the preset themselves; a backend query cannot, so it reads
  /// the same selection from here.
  ({DateTime from, DateTime to}) get statsRange {
    final from = _statsCustomFrom;
    final to = _statsCustomTo;
    if (from != null && to != null) {
      return (from: from, to: to);
    }
    final now = DateTime.now();
    return (from: now.subtract(_statsPreset), to: now);
  }

  /// The effective length of the currently selected analysis window — the
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
  /// selected analysis window, newest first — drives the events page.
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
  /// basis for the analysis views. Reads the store cache the controller keeps
  /// fresh via [reload] on every `update` ping and on resume.
  SplayTreeMap<int, int> archiveSince(Duration window) {
    final store = _store;
    if (store == null) {
      return SplayTreeMap<int, int>();
    }
    final now = DateTime.now();
    return store.archiveRange(now.subtract(window), now);
  }

  /// Long-term glucose archive over an explicit `[from, to]` window, keyed by
  /// epoch-minute — the source for a completed training's glucose overlay.
  SplayTreeMap<int, int> archiveBetween(DateTime from, DateTime to) {
    return _store?.archiveRange(from, to) ?? SplayTreeMap<int, int>();
  }

  /// Builds a reading from a persisted/IPC map. The trend field is keyed
  /// differently by the cached headline ('trend') and the live service payload
  /// ('trendTenths'); the other fixed fields aren't carried across.
  CgmReading _reading(Map map, String trendKey) {
    return CgmReading(
      secsSinceStart: map['secs'] as int? ?? 0,
      age: 0,
      sequence: 0,
      glucoseMgDl: map['mgdl'] as int?,
      predictedMgDl: map['pred'] as int? ?? 0,
      trendTenths: map[trendKey] as int? ?? 0,
      state: map['state'] as int? ?? 0,
      temperatureCentiC: map['tempC'] as int?,
    );
  }

  CgmReading? _latest;
  CgmReading? get latest => _latest;

  /// False when [_latest] was restored from cache (shown dimmed as "cached"),
  /// true once a live reading arrives from the service.
  bool _latestIsLive = false;
  bool get latestIsLive => _latestIsLive;

  /// Wall-clock time a live reading last arrived from the service. Fallback for
  /// the "last update" time when the sensor session start isn't known.
  DateTime? _latestAt;

  G7DeviceInfo _info = G7DeviceInfo();
  G7DeviceInfo get info => _info;

  /// The current glucose forecast overlay, fetched from the backend when the
  /// prediction setting is on (null when off or unavailable). [predictionBase]
  /// is the reading time the curve is anchored to; each point is that many
  /// minutes ahead of it.
  final GlucosePredictionFetcher _predictionFetcher =
      GlucosePredictionFetcher();
  final PredictionCache _predictionCache = PredictionCache();
  GlucosePrediction? _prediction;
  List<PredictionPoint>? get predictionCurve => _prediction?.points;
  DateTime? get predictionBase => _prediction?.base;

  /// Fetch a fresh forecast and update the overlay. Fire-and-forget.
  ///
  /// Only for the events the service isolate cannot see: opening the app, and
  /// the user changing the setting (both want an answer NOW rather than at the
  /// next reading). The steady 5-minutely refresh belongs to the service isolate
  /// — see `CgmTaskHandler._refreshPrediction` — because it is the only one alive
  /// while the phone sleeps; this class then just adopts its cache.
  ///
  /// A disabled setting clears the overlay (and its cache); a FAILED request
  /// keeps the last good forecast, so a transient network error doesn't blank
  /// the just-restored cache on launch.
  Future<void> refreshPrediction() async {
    final setting = await ProfilePredictionState.load();
    if (!setting.enabled) {
      await _setPrediction(null);
      return;
    }
    final result = await _predictionFetcher.fetch(
      setting.horizon,
      readings: _recentReadings(),
    );
    if (result == null) {
      return;
    }
    await _setPrediction(result);
  }

  /// How many recent readings to forward to the predictor (~30 min at the G7's
  /// 5-min cadence) so it can catch up after a sync outage.
  static const _predictionCatchUp = 6;

  /// The freshest readings (oldest→newest) with wall-clock times, drawn from the
  /// session series. Falls back to the single headline reading when the session
  /// clock isn't known yet (no [sensorStart]), else an empty list.
  List<(int, DateTime)> _recentReadings() {
    final start = _sensorStart;
    if (start == null) {
      final mgdl = currentMgdl;
      final at = lastUpdate;
      return mgdl != null && at != null ? [(mgdl, at)] : const [];
    }
    final keys = _byTime.keys.toList();
    final tail = keys.sublist(
      (keys.length - _predictionCatchUp).clamp(0, keys.length),
    );
    return [
      for (final secs in tail)
        (_byTime[secs]!, start.add(Duration(seconds: secs))),
    ];
  }

  Future<void> _setPrediction(GlucosePrediction? prediction) async {
    await _predictionCache.save(prediction);
    if (_disposed) {
      return;
    }
    _prediction = prediction;
    notifyListeners();
  }

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

  /// Current glucose value to display: the live reading, else the newest point
  /// of the (archive-backed) chart series — so a returning device shows its last
  /// synced value instead of nothing. Null only when there is no glucose at all.
  int? get currentMgdl {
    final live = _latest?.glucoseMgDl;
    if (live != null) {
      return live;
    }
    final series = byTime;
    return series.isEmpty ? null : series[series.lastKey()];
  }

  /// True when the headline value should be dimmed as "outdated". A fresh live
  /// reading is never stale. A restored/synced value is stale only when it has
  /// no known time (new sensor, value from the archive before the live clock has
  /// loaded) or is older than [_headlineStaleAfter] — a recently cached value
  /// restored on launch still reads as current.
  bool get currentIsStale {
    if (_latestIsLive) {
      return false;
    }
    final at = lastUpdate;
    if (at == null) {
      return true;
    }
    return DateTime.now().difference(at) > _headlineStaleAfter;
  }

  static const _headlineStaleAfter = Duration(minutes: 10);

  /// Trend for the headline: the live/cached reading's own trend, else derived
  /// from the last two archive points (a returning device with synced-only data).
  double? get displayTrendPerMin =>
      _latest?.trendMgDlPerMin ?? _archiveTrendPerMin;

  double? get _archiveTrendPerMin {
    final series = byTime;
    if (series.length < 2) {
      return null;
    }
    final lastKey = series.lastKey()!;
    final prevKey = series.lastKeyBefore(lastKey);
    if (prevKey == null) {
      return null;
    }
    final deltaMin = (lastKey - prevKey) / 60.0;
    if (deltaMin <= 0) {
      return null;
    }
    return (series[lastKey]! - series[prevKey]!) / deltaMin;
  }

  /// The whole log oldest-line-first (chronological), for copying/sharing.
  /// [_log] is stored newest-first, so it's reversed here.
  String get logText => _log.reversed.join('\n');

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    // Receive live updates pushed from the foreground-service isolate.
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    final store = await CgmStore.open();
    if (_disposed) {
      return;
    }
    _store = store;
    code.text = store.pairingCode ?? '';
    _restoreFromCache(store);
    _prediction = await _predictionCache.load();
    _advisoryDelivery = await const AdvisoryDeliveryStore().load();
    notifyListeners();
    // Show the cached forecast immediately, then fetch a fresh one (kept on
    // failure) so a reload isn't blank until the next reading.
    unawaited(refreshPrediction());
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
  void _restoreFromCache(CgmStore store) {
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
    if (key.isEmpty || !_isPaired(key)) {
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

  /// Whether the sensor under [key] is fully paired and can auto-reconnect —
  /// a stored G7 session key, or a Libre 3 BLE MAC from NFC activation.
  bool _isPaired(String key) {
    if (sensorType == SensorType.abbottLibre3) {
      return _store?.libreMac(key) != null;
    }
    return _store?.sessionKey(key) != null;
  }

  /// The Libre 3's BLE MAC from NFC activation (the sensor's stable address),
  /// shown on the sensor info page. Null for the G7 or before activation.
  String? get libreMac => _store?.libreMac(_key);

  /// The key cached data is stored under: the resolved key set by the read
  /// pipeline, falling back to the user serial (covers the brief window before
  /// the pipeline has resolved one).
  String get _key => _store?.resolvedKey ?? _store?.serial ?? '';

  void _append(String line) {
    if (_disposed) {
      return;
    }
    _log.insert(0, line);
    debugPrint(line);
    notifyListeners();
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
      // The service isolate fetches the forecast (it is the only one alive while
      // the phone sleeps) and pings once the cache holds a fresh one — so the UI
      // only mirrors it, exactly as it mirrors the store.
      case 'prediction':
        unawaited(_adoptCachedPrediction());
      case 'update':
        _reloadFromStore();
    }
  }

  /// Show whatever forecast the service isolate last cached. Unlike
  /// [refreshPrediction] this never hits the network — a null cache means the
  /// setting is off or nothing has been fetched yet, and clearing is correct.
  Future<void> _adoptCachedPrediction() async {
    final cached = await _predictionCache.load();
    if (_disposed) {
      return;
    }
    _prediction = cached;
    notifyListeners();
  }

  /// Re-read everything the service persisted (history, info, sensor start).
  /// Requires reloading the store's in-memory cache since the writes happened
  /// in the service isolate.
  Future<void> _reloadFromStore() async {
    await _readAdvisoryDelivery();
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

  /// Configure the foreground service's own notification, which doubles as the
  /// glucose readout on the lock screen.
  ///
  /// **Two channels, chosen by [NotificationSetting.lockscreenGlucose].**
  /// Android files an `IMPORTANCE_LOW` notification as "silent", and the lock
  /// screen setting most phones ship with ("hide silent notifications") then
  /// leaves it off the lock screen entirely — which is exactly what the user
  /// does or does not want. So the lock-screen style is `DEFAULT` importance and
  /// the discreet one is `LOW`. `playSound`/`enableVibration` are false either
  /// way, and DEFAULT rather than HIGH keeps it from popping up as a heads-up on
  /// every reading.
  ///
  /// **It has to be two channels, and switching needs a service restart.**
  /// Importance, sound and lock-screen behaviour are frozen when a channel is
  /// created and no later call moves them, so the setting cannot change one
  /// channel; it picks a different one, and the service has to be restarted onto
  /// it ([applyNotificationStyle]). [_pruneChannels] deletes the ones not in use,
  /// including the retired `insulink` channel from before this split.
  Future<void> _initForegroundTask() async {
    final onLockscreen = await NotificationSetting.lockscreenGlucose.load();
    final channelId = onLockscreen ? _lockscreenChannel : _quietChannel;
    await _pruneChannels(channelId);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: await _strings.get('service.channel.name'),
        channelDescription: await _strings.get('service.channel.description'),
        channelImportance: onLockscreen
            ? NotificationChannelImportance.DEFAULT
            : NotificationChannelImportance.LOW,
        priority: onLockscreen
            ? NotificationPriority.DEFAULT
            : NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
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

  /// The status-bar icon for the service notification.
  ///
  /// Without one the plugin falls back to the app's LAUNCHER icon, and Android
  /// draws a status-bar icon as a silhouette of whatever it is given, so a
  /// full-colour launcher icon comes out as a plain white circle. This is the
  /// same monochrome drawable the alarms use, named through a manifest
  /// `meta-data` entry because that is the only way the plugin takes a drawable.
  ///
  /// Only needed at [FlutterForegroundTask.startService]: an `updateService`
  /// that passes none keeps the stored one.
  static const _notificationIcon = NotificationIcon(
    metaDataName: 'de.insulink.NOTIFICATION_ICON',
  );

  /// The service channel shown on the lock screen, and the discreet one that is
  /// not. See [_initForegroundTask] for why the style is baked into the id.
  static const _lockscreenChannel = 'insulink_glucose';
  static const _quietChannel = 'insulink_glucose_quiet';

  /// Delete every service channel except [keep], so the app's notification
  /// settings never list entries that control nothing: the style the user turned
  /// off, and `insulink`, the single channel both of these replaced.
  Future<void> _pruneChannels(String keep) async {
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channelId in const [
      'insulink',
      _lockscreenChannel,
      _quietChannel,
    ]) {
      if (channelId != keep) {
        await android?.deleteNotificationChannel(channelId: channelId);
      }
    }
  }

  /// Move the running service onto the channel the style setting now names.
  ///
  /// A restart, because the style lives in the channel and a channel cannot be
  /// changed after it is created. It also costs a fresh BLE scan, which is why
  /// nothing else calls this: it is a deliberate tap in the settings, not
  /// something that can fire on its own. The restart is stamped so the
  /// stale-data recovery does not immediately restart again on top of it
  /// (`_restartCooldown`). With no service running there is nothing to do, and
  /// the next start reads the setting anyway.
  Future<void> applyNotificationStyle() async {
    if (!await FlutterForegroundTask.isRunningService || _disposed) {
      return;
    }
    await _initForegroundTask();
    _lastRestartAt = DateTime.now();
    await FlutterForegroundTask.restartService();
    if (_disposed) {
      return;
    }
    await _refreshServiceState();
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
      await _initForegroundTask();
      // A detection-only service (started by ensureDetectionService) has no
      // connectedDevice FGS type and a stale empty pairing code, so replace it
      // with a fresh, sensor-aware isolate rather than reusing it.
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      await _startService(forSensor: true);
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
  /// Says this sensor is gone: locally, so the card goes at once, and to the
  /// ACCOUNT, so it stays gone.
  ///
  /// The local flag alone was no use in the one situation the offer exists for.
  /// It is per install, and the card is shown after a reinstall, so the sensor
  /// came back offering itself every time. Best-effort towards the account,
  /// including a thrown call: a phone with no signal must still be able to
  /// dismiss a card.
  Future<void> dismissRestore(String sensorId) async {
    await _store?.setRestoreDismissed(sensorId);
    await _tellTheAccountSensorIsGone(sensorId);
  }

  Future<void> _tellTheAccountSensorIsGone(String sensorId) async {
    try {
      await const SensorSync().discard(sensorId, null);
    } catch (error) {
      _append('telling the account the sensor is gone failed: $error');
    }
  }

  /// Adopt the sensor the backend has on file (offered on a fresh install when
  /// no sensor is set up locally): restore its identity into the store, then
  /// start reading.
  ///
  /// The G7 reconnects straight from the restored identity. A Libre 3 CANNOT:
  /// its BLE PIN is reissued on every NFC scan and the sensor honours only the
  /// latest one, so this restores the recognisable parts (type, MAC, session
  /// start) and does NOT start the service — the caller sends the user through
  /// [activateLibre3] for a fresh PIN. Returns whether reading has started.
  Future<bool> restoreSensor(SensorRestore restore) async {
    final store = _store;
    if (store == null) {
      return false;
    }
    await store.saveSensorType(restore.sensorType);
    await store.saveIdentity(
      serial: '',
      pairingCode: restore.pairingCode ?? '',
    );
    await store.saveResolvedKey(restore.resolvedKey);
    await store.saveBackendSensorId(restore.resolvedKey, restore.sensorId);
    if (restore.sensorType == SensorType.abbottLibre3) {
      await _restoreLibreIdentity(store, restore);
    } else {
      await _restoreG7Identity(store, restore);
    }
    code.text = restore.pairingCode ?? '';
    _restoreFromCache(store);
    notifyListeners();
    if (restore.sensorType == SensorType.abbottLibre3) {
      return false;
    }
    await start();
    return true;
  }

  Future<void> _restoreG7Identity(CgmStore store, SensorRestore restore) async {
    await store.saveDeviceId(restore.resolvedKey, restore.deviceId!);
    await store.saveSessionKeyHex(restore.resolvedKey, restore.sessionKeyHex!);
    final infoJson = restore.infoJson;
    if (infoJson != null) {
      final start = restore.sensorStartMs;
      await store.saveInfo(
        restore.resolvedKey,
        G7DeviceInfo.fromJson(infoJson),
        start == null ? null : DateTime.fromMillisecondsSinceEpoch(start),
      );
    }
  }

  Future<void> _restoreLibreIdentity(
    CgmStore store,
    SensorRestore restore,
  ) async {
    if (restore.libreMac != null) {
      await store.saveLibreMac(restore.resolvedKey, restore.libreMac!);
    }
    final start = restore.sensorStartMs;
    if (start != null) {
      await store.saveSensorStart(
        restore.resolvedKey,
        DateTime.fromMillisecondsSinceEpoch(start),
      );
    }
  }

  Future<void> _startService({required bool forSensor}) async {
    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      serviceTypes: await _serviceTypes(forSensor: forSensor),
      notificationTitle: 'Insulink',
      notificationText: await _strings.get('service.connecting'),
      notificationIcon: _notificationIcon,
      callback: startCallback,
    );
    if (result is ServiceRequestSuccess) {
      _append('background service started');
    } else if (result is ServiceRequestFailure) {
      _append('service start failed: ${result.error}');
    }
  }

  /// Service types for the foreground service. `connectedDevice` (which requires
  /// a held BLE runtime permission at `startForeground` on Android 14+) is added
  /// only for a sensor connection; a detection-only service ([forSensor] false)
  /// omits it so it needs no BLE permission. `location` is added whenever the OS
  /// location permission is held — it's what lets the service sample GPS in the
  /// background (see [BackgroundLocationSampler]) and is the sole type of a
  /// detection-only service. Glucose reading never depends on location.
  Future<List<ForegroundServiceTypes>> _serviceTypes({
    required bool forSensor,
  }) async {
    final types = <ForegroundServiceTypes>[];
    // `connectedDevice` for a sensor, and also for a detection-only service when
    // Bluetooth is already permitted — that service hosts the live heart-rate
    // band (see CgmTaskHandler._startBackgroundHr), which on Android 14+ needs
    // this FGS type. Gated on the held permission so a service never declares a
    // type it lacks the runtime permission for.
    if (forSensor || await Permission.bluetoothConnect.isGranted) {
      types.add(ForegroundServiceTypes.connectedDevice);
    }
    if (await Permission.location.isGranted) {
      types.add(ForegroundServiceTypes.location);
    }
    return types;
  }

  /// Ensure the background service runs so cardio auto-detection keeps working
  /// even without a CGM sensor — the GPS/activity samplers and the detection
  /// scan live in the service isolate (see [CgmTaskHandler]). Called when the
  /// Sport tab opens. No-op when a sensor is paired (the sensor path already
  /// runs the service) or the service is already up. Starts a LOCATION-typed
  /// service WITHOUT prompting — only if location + notifications are already
  /// granted (both requested in onboarding) — so opening the Sport tab never
  /// triggers a permission dialog.
  /// [force] skips only the battery-saver check — a manually started cardio
  /// recording needs this service for its route even while the saver has
  /// auto-detection paused (`CardioTrainingState.startTraining` starts no service
  /// of its own). The permission checks below always apply.
  Future<void> ensureDetectionService({bool force = false}) async {
    if (_busy || hasSensor) {
      return;
    }
    // Nothing to host: with detection paused, a sensorless service would only
    // hold the wake + Wi-Fi lock. Biggest saving for a user with no CGM sensor,
    // whose service today comes up merely from opening the Sport tab.
    if (!force && (await ProfileBatteryState.loadActive()).pausesDetection) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    if (!await Permission.location.isGranted) {
      return;
    }
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      return;
    }
    await _initForegroundTask();
    await _startService(forSensor: false);
    await _refreshServiceState();
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
  /// analysis history survives switching to a new sensor; only the current-session
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
    // The account too, or it offers this sensor straight back after the next
    // reinstall. Read before the local clear, which is what holds the id.
    final backendId = _store?.backendSensorId(key);
    if (backendId != null) {
      await _tellTheAccountSensorIsGone(backendId);
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

  /// Insulin the service gave from a notification button while the app was not
  /// involved, or null once the user has seen it. Mirrored here like everything
  /// else the service isolate writes, and re-read on the same two triggers: a
  /// resume, and the service's own "something changed" ping.
  AdvisoryDelivery? get advisoryDelivery => _advisoryDelivery;
  AdvisoryDelivery? _advisoryDelivery;

  Future<void> _readAdvisoryDelivery() async {
    _advisoryDelivery = await const AdvisoryDeliveryStore().load();
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Take the delivery banner down. Cleared in storage too, so it does not come
  /// back on the next reload.
  Future<void> dismissAdvisoryDelivery() async {
    _advisoryDelivery = null;
    if (!_disposed) {
      notifyListeners();
    }
    await const AdvisoryDeliveryStore().clear();
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
