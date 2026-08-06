import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../google_health/fitbit_heart_rate_monitor.dart';
import '../../google_health/google_health_importer.dart';
import '../../google_health/intraday_pulse_store.dart';
import '../../google_health/pulse_sync.dart';
import '../../profile/battery/profile_battery_state.dart';
import '../../profile/glucose/profile_glucose_state.dart';
import '../../profile/notifications/profile_live_notification_state.dart';
import '../../rust/frb_generated.dart';
import '../../sport/sport_store.dart';
import '../../sport/sport_sync.dart';
import '../../sport/training/activity_recognition_sampler.dart';
import '../../sport/training/background_location_sampler.dart';
import '../../sport/training/cardio_detection_runner.dart';
import '../../profile/prediction/profile_prediction_state.dart';
import 'alarms.dart';
import '../cgm_connection.dart';
import '../event_sync.dart';
import '../glucose_prediction.dart';
import '../glucose_sync.dart';
import '../protocol/connection.dart';
import '../sensor_sync.dart';
import '../cgm_store.dart';
import '../../libre3/libre3_connection.dart';
import '../../libre3/libre3_crypto.dart';

/// Entry point for the foreground-service isolate. Must be a top-level function
/// annotated `vm:entry-point` so it survives tree-shaking and can be invoked by
/// the native service after the UI/activity (and its isolate) are gone.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(CgmTaskHandler());
}

/// Hosts the active [CgmConnection] inside the Android foreground service. This isolate
/// keeps the BLE link and the read pipeline alive while the app is backgrounded
/// or fully closed, persisting glucose to [CgmStore] and pushing live updates
/// back to the UI over the foreground-task data channel.
///
/// Robustness is the whole point of this class: the isolate must survive a
/// failed startup, a wedged connect, a half-open BLE link, and a BLE stack that
/// stops delivering — without a UI around to notice. The [onRepeatEvent]
/// watchdog (cadence from `ForegroundTaskOptions.eventAction`) is the only thing
/// that runs while the phone is asleep, so it owns every recovery path.
class CgmTaskHandler extends TaskHandler {
  CgmConnection? _conn;
  G7AlarmManager? _alarms;
  CgmStore? _store;
  String _serial = '';
  String _pairingCode = '';

  /// Whether an actual CGM sensor is set up, so the BLE pipeline should run. A
  /// RECONNECTING sensor authenticates with its stored session key / resolved
  /// BLE id — NOT the pairing code — so the pairing code alone is not a reliable
  /// "has sensor" signal: Libre 3 never stores one, and a G7's is empty after a
  /// backend restore. Keying the connect gate on the code alone stopped an
  /// auto-restarted service (e.g. after an app update) from ever reconnecting.
  /// A detection-only service (no sensor) has neither a code nor a resolved key.
  bool get _sensorConfigured =>
      _pairingCode.isNotEmpty || (_store?.resolvedKey ?? '').isNotEmpty;

  /// The Rust J-PAKE core can be initialised exactly once per isolate; guard it
  /// so the watchdog's recovery re-init doesn't re-call `RustLib.init()` (which
  /// throws if already initialised).
  bool _coreReady = false;

  /// Piggybacks periodic GPS sampling on this already-running foreground service
  /// (flutter_foreground_task hosts only one), independent of the BLE pipeline.
  /// No-ops unless location is permitted — glucose reading never depends on it.
  late final BackgroundLocationSampler _locationSampler =
      BackgroundLocationSampler(
        onLog: _log,
        isStill: () => _activitySampler.isStill,
        isDetectionPaused: () => _batteryMode.pausesDetection,
      );

  /// Logs OS activity-recognition changes (cycling vs. in-vehicle) so the cardio
  /// auto-detector can reject bus/train rides. Permission-gated; no-op otherwise.
  final ActivityRecognitionSampler _activitySampler =
      ActivityRecognitionSampler();

  /// Scans the GPS + activity logs for finished trainings and raises a
  /// confirm-notification for each. Runs off the watchdog, throttled by
  /// [_detectEvery].
  final CardioDetectionRunner _detectionRunner = CardioDetectionRunner();

  /// When training detection last ran, so it doesn't re-decode the whole location
  /// log every watchdog tick.
  DateTime? _lastDetectionAt;
  static const _detectEvery = Duration(minutes: 2);

  /// The battery saver in force, re-read once per watchdog tick by
  /// [_applyBatteryMode]. Cached rather than loaded at each use so the 10 s GPS
  /// tick doesn't gain a secure-storage read, and so every gate below reads the
  /// same value within a tick.
  BatteryMode _batteryMode = BatteryMode.off;

  /// When the live heart-rate poll last ran, and its cadence. Only polls while a
  /// Google Health is connected; pushes fresh samples to the UI's GoogleHealthState.
  DateTime? _lastHrPollAt;
  int? _lastHrPushedAtMs;
  /// Health Connect poll cadence, stretched by the battery saver.
  Duration get _hrPollEvery => _batteryMode.slowsHeartRatePoll
      ? const Duration(minutes: 5)
      : const Duration(seconds: 60);
  // A background Health Connect sample lags more than the main isolate's 1 Hz
  // BLE reading, so the relay tolerates more age than GoogleHealthState's 5 s
  // before it counts a value as too stale to pass to the panel as live.
  static const _liveRelayMaxAge = Duration(minutes: 3);

  /// Live-BLE heart-rate reader hosted HERE while the app is backgrounded or
  /// closed, so bpm keeps streaming (~1 Hz) when the UI isolate — and the band
  /// link it owns — is gone. Ownership is exclusive: the UI runs the band while
  /// foregrounded and hands it over via an [onReceiveData] `hrOwner` message on
  /// going to background, so the two isolates never fight over the one GATT
  /// link. Null until the first handover; the Health Connect poll below is the
  /// fallback when no band streams. Fresh readings go to the UI, the account's
  /// live-pulse cache, and (buffered) the durable pulse curve.
  FitbitHeartRateMonitor? _hrMonitor;
  final IntradayPulseStore _pulseStore = const IntradayPulseStore();
  DateTime? _lastPulseFlush;

  /// Dedicated timer so GPS can be sampled far more often than the ~30s watchdog
  /// (up to every 10s while moving / recording a training). The sampler itself
  /// decides the effective cadence; this just gives it the chance every 10s.
  Timer? _locationTimer;

  /// Wall-clock of the last live reading (seeded at startup so a service that
  /// never produces anything still escalates). The G7 delivers ~every 5 min, so
  /// "time since last reading" — not BLE connection state, which is normally
  /// "disconnected" between deliveries — is the real health signal.
  DateTime? _lastReadingAt;

  /// When the in-flight `connect()` began, to detect a wedged attempt.
  DateTime? _connectStartedAt;

  /// Set once we trigger a full service restart, so we don't fire it twice
  /// before the isolate is torn down and replaced.
  bool _restarting = false;

  /// All watchdog cadence thresholds now come from the active connection's
  /// [CgmConnection.timing], because the G7 (connect/deliver/drop every ~5 min)
  /// and the Libre 3 (continuous link, ~1-min stream) have very different
  /// "healthy silence" windows. See [CgmTiming].
  CgmTiming get _timing => _conn?.timing ?? _fallbackTiming;

  /// Used only in the brief window before [_conn] exists (the restart
  /// escalation can run then). Matches the G7's generous values.
  static const _fallbackTiming = CgmTiming(
    staleAfter: Duration(minutes: 12),
    restartAfter: Duration(minutes: 25),
    processRestartAfter: Duration(minutes: 35),
    connectStuckAfter: Duration(minutes: 7),
    reconnectBackoff: Duration(minutes: 3),
    expectsContinuousLink: false,
  );

  /// Wall-clock of the last actual EGV delivery (null until the first), used
  /// only for the reconnect backoff. Distinct from [_lastReadingAt], which is
  /// SEEDED at startup for the restart escalation — seeding this one would
  /// wrongly suppress the very first connect.
  DateTime? _lastDeliveryAt;

  /// Value+trend the ongoing notification currently shows, so repeats are
  /// dropped — see [_updateNotification].
  String? _shownNotification;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // The tick only decides WHICH location stream should be open (and does the
    // sparse at-rest poll) — the recording cadence itself is the stream's, on
    // the platform. So it doesn't have to be fast, and every tick costs a
    // secure-storage read; the price is that a pause takes up to one tick to
    // stop recording.
    _locationTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _locationSampler.tick(),
    );
    _batteryMode = await ProfileBatteryState.loadActive();
    if (!_batteryMode.pausesDetection) {
      _activitySampler.start();
    }
    unawaited(_applyTrainingDecisions());
    // Host the live band the whole time this service runs, so bpm keeps
    // streaming with the app backgrounded OR fully closed — no dependence on the
    // dying UI isolate to hand it over. Known-band-only (never scans), so it is a
    // no-op until a Fitbit has been paired and cannot fight the G7 scanner.
    if (!_batteryMode.pausesBand) {
      _startBackgroundHr();
    }
    // With no sensor paired the service still runs (samplers + detection above)
    // but has nothing to connect to, so skip the BLE connect.
    if (await _ensureReady() && _sensorConfigured) {
      _startConnect();
    }
  }

  /// Idempotently bring the isolate to a state where [_conn] exists: init the
  /// Rust core (once), the alarm manager + store (once), and build the pipeline.
  /// Safe to call again from the watchdog to recover a startup that threw —
  /// without this, a single failure in `onStart` left a dead service that the
  /// watchdog could never revive (it bails on a null `_conn`).
  Future<bool> _ensureReady() async {
    if (_conn != null) {
      return true;
    }
    try {
      if (!_coreReady) {
        // Fresh isolate: the Rust J-PAKE core must be initialised here too.
        await RustLib.init();
        _coreReady = true;
      }
      if (_store == null) {
        final store = await CgmStore.open();
        _store = store;
        final alarms = G7AlarmManager(FlutterLocalNotificationsPlugin(), store);
        await alarms.init();
        _alarms = alarms;
        _serial = store.serial ?? '';
        _pairingCode = store.pairingCode ?? '';
      }
      _buildConnection();
      // Seed the health clock so a service that never gets a first reading still
      // escalates to a restart instead of retrying silently forever.
      _lastReadingAt ??= DateTime.now();
      return true;
    } catch (e) {
      _log('service init error: $e');
      return false;
    }
  }

  /// Build the read pipeline for the paired sensor. The strategy is chosen by
  /// [CgmStore.sensorType]; both implement [CgmConnection] and wire the SAME
  /// callbacks (below), so the rest of this handler drives them identically.
  void _buildConnection() {
    final store = _store!;
    _conn = switch (store.sensorType) {
      SensorType.dexcomG7 => G7Connection(
        store: store,
        serial: _serial,
        pairingCode: _pairingCode,
        onLog: _log,
        onReading: _handleReading,
        onUpdate: _handleUpdate,
        onConnectionState: _handleConnectionState,
        onArchive: _handleArchive,
      ),
      SensorType.abbottLibre3 => Libre3Connection(
        store: store,
        crypto: Libre3NativeCrypto(),
        onLog: _log,
        onReading: _handleReading,
        onUpdate: _handleUpdate,
        onConnectionState: _handleConnectionState,
        onArchive: _handleArchive,
      ),
    };
  }

  /// A reading means the link is healthy — reset the health clock, alarm, mirror
  /// the sensor to the account, check expiry/halftime, and push to the UI. Shared
  /// by both sensor strategies.
  void _handleReading(CgmReading reading) {
    _lastReadingAt = DateTime.now();
    _lastDeliveryAt = _lastReadingAt;
    final store = _store!;
    final alarms = _alarms!;
    alarms.onReading();
    _updateNotification(reading.glucoseMgDl, reading.trendMgDlPerMin);
    if (reading.glucoseMgDl != null) {
      alarms.check(reading.glucoseMgDl, reading.trendMgDlPerMin);
      alarms.checkAdvisory(reading.glucoseMgDl, reading.trendMgDlPerMin);
    }
    SensorSync().sync(store);
    // Fall back to the active sensor's nominal lifetime when the connection
    // hasn't reported its own session length (else the halftime/expiry reminders
    // fire on the G7 schedule for a Libre 3).
    final key = store.resolvedKey ?? _serial;
    final lifetime =
        _conn?.sessionLengthSec ?? store.sensorType.sessionLengthSec;
    alarms.checkExpiry(
      store: store,
      key: key,
      sessionLengthSec: lifetime,
      secsSinceStart: reading.secsSinceStart,
    );
    alarms.checkHalftime(
      store: store,
      key: key,
      sessionLengthSec: lifetime,
      secsSinceStart: reading.secsSinceStart,
    );
    FlutterForegroundTask.sendDataToMain({
      't': 'reading',
      'mgdl': reading.glucoseMgDl,
      'pred': reading.predictedMgDl,
      'trendTenths': reading.trendTenths,
      'state': reading.state,
      'secs': reading.secsSinceStart,
      'tempC': reading.temperatureCentiC,
    });
    unawaited(_refreshPrediction(reading));
  }

  /// Fetch a fresh forecast into [PredictionCache] and tell the UI to adopt it.
  ///
  /// This isolate owns the periodic fetch because it is the only one alive while
  /// the phone sleeps — and the sleeping phone is exactly when the advisory
  /// matters. The UI used to fetch instead, which left [G7AlarmManager] falling
  /// back to the bare trend line the moment the app was closed.
  ///
  /// Deliberately NOT awaited before [G7AlarmManager.checkAdvisory] above: a
  /// forecast is a network round-trip (up to 10 s plus retries) and an alarm must
  /// not wait on the network. The advisory therefore reads the PREVIOUS reading's
  /// curve — at the G7's 5-min cadence that is well inside the 10-min freshness
  /// window, and it is what the UI-driven fetch already did.
  Future<void> _refreshPrediction(CgmReading reading) async {
    final mgdl = reading.glucoseMgDl;
    final store = _store;
    if (mgdl == null || store == null) {
      return;
    }
    if (_batteryMode.pausesPrediction) {
      return;
    }
    final setting = await ProfilePredictionState.load();
    if (!setting.enabled) {
      return;
    }
    final result = await GlucosePredictionFetcher().fetch(
      setting.horizon,
      readings: _predictionAnchor(store, reading, mgdl),
    );
    if (result == null) {
      return;
    }
    await PredictionCache().save(result);
    FlutterForegroundTask.sendDataToMain({'t': 'prediction'});
  }

  /// The reading to anchor the forecast to, with a wall-clock time.
  ///
  /// Glucose reaches the backend through a debounced [GlucoseSync], so the tip
  /// the predictor sees in the DB can lag by minutes — this hands it the value we
  /// just read. Timed off the sensor's own session clock (like the UI does) so
  /// the point lands in the right 5-min bucket; an unknown session start means we
  /// cannot place it in wall-clock time at all, so we send nothing and let the
  /// predictor anchor to its stored tip.
  List<(int, DateTime)> _predictionAnchor(
    CgmStore store,
    CgmReading reading,
    int mgdl,
  ) {
    final key = store.resolvedKey ?? _serial;
    final start = key.isEmpty ? null : store.loadSensorStart(key);
    if (start == null) {
      return const [];
    }
    return [(mgdl, start.add(Duration(seconds: reading.secsSinceStart)))];
  }

  void _handleUpdate() {
    _updateNotification(_conn?.latestMgDl, _conn?.latestTrendPerMin);
    FlutterForegroundTask.sendDataToMain({'t': 'update'});
  }

  void _handleConnectionState(bool connected) {
    FlutterForegroundTask.sendDataToMain({'t': 'conn', 'connected': connected});
  }

  void _handleArchive(Map<int, int> readings) {
    GlucoseSync().queue(readings, _log);
    // Flush any service-isolate events (alarm zones, signal loss, new sensor)
    // to the backend; retries on the next reading if it fails.
    EventSync().sync(_store!, _log);
  }

  /// Watchdog: the only code that runs while the phone is asleep. Drives every
  /// recovery path — rebuild a failed startup, reconnect a dropped link, reset a
  /// wedged connect, drop a half-open link, and restart the whole service if the
  /// BLE stack has stopped delivering. Cadence: `eventAction` in the UI.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _watchdog();
    // Chained, not fired in parallel, so detection sees THIS tick's mode — the
    // whole point is that toggling the saver takes effect without a restart.
    unawaited(_applyBatteryMode().then((_) => _maybeDetectTraining()));
    // ponytail: rides the CGM service (the app's only foreground service), so
    // background HR runs only while glucose reading is active. Standalone HR
    // would need its own service — out of scope.
    _maybePollHeartRate();
    // Apply Confirm/Reject taps buffered by the notification-action isolate,
    // which can't reach secure storage itself (see SportStore.recordTrainingDecision).
    unawaited(_applyTrainingDecisions());
  }

  /// Drain the buffered Confirm/Reject taps and push the confirmed trainings to
  /// the account. The push is what makes a confirm survive: without it the
  /// training exists only on this device, and the next pull replaces the local
  /// list with the account's — which never heard about it.
  Future<void> _applyTrainingDecisions() async {
    if (await const SportStore().applyTrainingDecisions()) {
      SportSync().pushTrainings();
    }
  }

  /// Re-read the battery saver and bring the two long-lived subscriptions in
  /// line with it: the OS activity-recognition stream and the hosted Fitbit band.
  ///
  /// Both `start` calls are idempotent, so this can run on every tick. Doing it
  /// here rather than at service start is what lets a saver be switched on or off
  /// mid-session — the settings live in secure storage, which this isolate can
  /// only poll (it cannot observe the UI's notifier). The remaining gates
  /// ([_maybeDetectTraining], the GPS tick, the HR cadence, the forecast fetch)
  /// read the cached [_batteryMode] this sets.
  Future<void> _applyBatteryMode() async {
    _batteryMode = await ProfileBatteryState.loadActive();
    if (_batteryMode.pausesDetection) {
      _activitySampler.dispose();
    } else {
      await _activitySampler.start();
    }
    if (_batteryMode.pausesBand) {
      await _stopBackgroundHr();
    } else {
      _startBackgroundHr();
    }
  }

  /// Runs cardio auto-detection at most every [_detectEvery]; each new training
  /// is added to the pending list and raises a confirm-notification.
  Future<void> _maybeDetectTraining() async {
    if (_batteryMode.pausesDetection) {
      return;
    }
    final last = _lastDetectionAt;
    if (last != null && DateTime.now().difference(last) < _detectEvery) {
      return;
    }
    _lastDetectionAt = DateTime.now();
    try {
      await _detectionRunner.run(
        (training) async => _alarms?.notifyTrainingDetected(training),
      );
    } catch (e) {
      _log('training detection error: $e');
    }
  }

  /// Polls Health Connect for the latest heart rate at most every [_hrPollEvery]
  /// while a Google Health is connected, and pushes a fresher sample to the UI's
  /// GoogleHealthState. The connected flag is read fresh from storage — the service
  /// isolate can't observe the UI's GoogleHealthState.
  Future<void> _maybePollHeartRate() async {
    // A hosted band streaming live bpm is fresher than Health Connect (which
    // lags the band by hours); don't let a stale poll overwrite it.
    if (_hrMonitor?.status == FitbitHrStatus.streaming) {
      return;
    }
    final last = _lastHrPollAt;
    if (last != null && DateTime.now().difference(last) < _hrPollEvery) {
      return;
    }
    _lastHrPollAt = DateTime.now();
    if (await const FlutterSecureStorage().read(
          key: 'google_health.connected',
        ) !=
        'true') {
      return;
    }
    final latest = await GoogleHealthImporter().latestHeartRate();
    final atMs = latest.atMs;
    if (latest.hr == null || atMs == null) {
      return;
    }
    if (_lastHrPushedAtMs != null && atMs <= _lastHrPushedAtMs!) {
      return;
    }
    _lastHrPushedAtMs = atMs;
    FlutterForegroundTask.sendDataToMain({
      't': 'hr',
      'v': latest.hr,
      'at': atMs,
    });
    // Also relay to the account's live-pulse cache so the web panel's workout
    // vitals keep updating while the app is backgrounded / the screen is off /
    // the app was swiped away — the main isolate's BLE relay is frozen then, but
    // this foreground-service isolate keeps running. Guarded on freshness so a
    // stale Health Connect sample is not passed off as live.
    // ponytail: background cadence is the 60 s HR poll, not the 1 Hz the BLE
    // relay manages in the foreground — enough for a vitals bar, and streaming
    // BLE from this isolate would be a far bigger change. Bump _hrPollEvery (or
    // host the band here) if a workout needs tighter background resolution.
    if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(atMs)) <
        _liveRelayMaxAge) {
      PulseSync().pushLive(latest.hr!);
    }
  }

  Future<void> _watchdog() async {
    try {
      // Recover a startup that threw before the pipeline existed.
      if (_conn == null) {
        if (await _ensureReady() && _sensorConfigured) {
          _log('watchdog: pipeline rebuilt — connecting…');
          _startConnect();
        }
        return;
      }
      // No sensor paired: the service is running only to host background
      // training auto-detection (driven by onRepeatEvent). Skip all BLE
      // reconnect/restart escalation — there is nothing to connect to, and a
      // restart/exit here would needlessly churn (or kill) the detection host.
      if (!_sensorConfigured) {
        return;
      }
      final connection = _conn!;

      // Warn the user once the link has been silent for 15 min while a sensor
      // is linked (best-effort; toggleable in profile notification settings).
      final last = _lastReadingAt;
      if (last != null) {
        _alarms?.checkConnectionLost(
          sensorLinked: _sensorConfigured,
          sinceLastReading: DateTime.now().difference(last),
        );
      }

      // Last resort: no data for far too long ⇒ the in-process BLE stack is
      // likely wedged (reconnect attempts can't clear it). Two escalation steps:
      //  1. restartService() — cheap: a fresh isolate + Rust core, same process.
      //     Clears an isolate-level deadlock but NOT a wedged native BLE scanner,
      //     because the scanner state lives in the (unchanged) OS process.
      //  2. If we ALREADY did (1) recently and data is still absent, the native
      //     scanner is wedged — the Android-13+ failure where startScan silently
      //     returns nothing and only a Bluetooth toggle (turnOff() is a no-op on
      //     13+) or an app restart recovers it. Kill the process so Android's
      //     sticky foreground-service restart brings up a fresh process WITH a
      //     fresh BLE stack — what the user was doing by hand.
      if (!_restarting &&
          last != null &&
          DateTime.now().difference(last) > _timing.restartAfter) {
        _restarting = true;
        final lastRestart = _store?.lastServiceRestartAt;
        final restartedRecently =
            lastRestart != null &&
            DateTime.now().difference(lastRestart) <
                _timing.processRestartAfter;
        if (restartedRecently) {
          _log(
            'watchdog: still no data after a service restart — native BLE '
            'stack wedged, restarting the whole process',
          );
          await _conn?.dispose();
          // ponytail: exit(0) relies on the sticky FGS being recreated by
          // Android (reliable on Pixel/AOSP). If an OEM doesn't restart it, the
          // app is dead until reopened — i.e. no worse than today's manual fix.
          exit(0);
        }
        _log('watchdog: no data for too long — restarting service');
        await _store?.markServiceRestart();
        await FlutterForegroundTask.restartService();
        return;
      }

      // A wedged connect: the transport bounds each step, but force-reset if the
      // attempt still exceeds the cap so it can't pin the watchdog forever.
      if (connection.isConnecting) {
        final since = _connectStartedAt;
        if (since != null &&
            DateTime.now().difference(since) > _timing.connectStuckAfter) {
          _log('watchdog: connect wedged — resetting');
          await connection.dispose();
        }
        return;
      }

      // The G7 drops the link after each ~5-min delivery, so "not connected" is
      // the NORMAL resting state — reconnect to catch the next delivery. Hold off
      // for the reconnect backoff after a delivery on BOTH paths: the sensor won't
      // advertise again for ~5 min, and arming early just makes the radio hunt a
      // device that isn't there yet. This backoff applies to autoConnect too —
      // autoConnect finds the device via the OS's internal background scan, which
      // is subject to the SAME Android "scanning too frequently" throttle, so
      // arming immediately after every drop trips it and the reconnect then never
      // completes (observed: repeated arms → 6-min timeout). A MISSED delivery
      // leaves [_lastDeliveryAt] old, so we reconnect normally when it counts.
      if (!connection.isConnected) {
        final delivered = _lastDeliveryAt;
        if (delivered != null &&
            DateTime.now().difference(delivered) < _timing.reconnectBackoff) {
          return;
        }
        _log('watchdog: reconnecting…');
        _startConnect();
        return;
      }

      // Connected but silent past the stale window ⇒ a half-open link that will
      // never deliver — drop it so the next tick reconnects cleanly.
      if (last != null &&
          DateTime.now().difference(last) > _timing.staleAfter) {
        _log('watchdog: link stale — forcing reconnect');
        await connection.dispose();
      }
    } catch (e) {
      _log('watchdog error: $e');
    }
  }

  /// Start a connect attempt, stamping the time so a wedged attempt can be
  /// detected.
  void _startConnect() {
    _connectStartedAt = DateTime.now();
    _conn?.connect();
  }

  void _log(String line) {
    FlutterForegroundTask.sendDataToMain({'t': 'log', 'line': line});
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'disconnect') {
      _conn?.dispose();
    }
  }

  /// Host the live band for as long as this service runs. Idempotent, and
  /// known-band-only so it never scans (no G7 scanner contention) and no-ops
  /// until a Fitbit has been paired — so it is safe to call unconditionally on
  /// every service start, sensor or not.
  void _startBackgroundHr() {
    if (_hrMonitor != null) {
      return;
    }
    final monitor = FitbitHeartRateMonitor();
    _hrMonitor = monitor;
    monitor.addListener(_onBackgroundHr);
    unawaited(monitor.start(knownOnly: true));
  }

  Future<void> _stopBackgroundHr() async {
    final monitor = _hrMonitor;
    if (monitor == null) {
      return;
    }
    _hrMonitor = null;
    monitor.removeListener(_onBackgroundHr);
    await monitor.stop();
  }

  /// Relay a fresh band reading to the UI, the account's live-pulse cache and
  /// (buffered) the durable curve. Mirrors `GoogleHealthState._onBleHr`; the
  /// monitor also notifies on status changes, so a stale/absent bpm is ignored.
  void _onBackgroundHr() {
    final monitor = _hrMonitor;
    final bpm = monitor?.bpm;
    final at = monitor?.lastUpdate;
    if (bpm == null || at == null) {
      return;
    }
    if (DateTime.now().difference(at) > _liveRelayMaxAge) {
      return;
    }
    FlutterForegroundTask.sendDataToMain({
      't': 'hr',
      'v': bpm,
      'at': at.millisecondsSinceEpoch,
    });
    PulseSync().pushLive(bpm);
    unawaited(_flushBackgroundPulse(monitor!));
  }

  /// Persist + sync the band samples buffered since the last flush — once a
  /// minute while a viewer watches, every five minutes otherwise. The pulse
  /// store buckets to one point per minute either way; the sparser idle cadence
  /// is about the POST, which wakes the cellular radio out of its low-power
  /// state each time. Mirrors `GoogleHealthState._flushLivePulse`.
  Future<void> _flushBackgroundPulse(FitbitHeartRateMonitor monitor) async {
    final now = DateTime.now();
    final cutoff = _lastPulseFlush;
    final flushGap = PulseSync().liveViewer && !_batteryMode.pausesBand
        ? const Duration(minutes: 1)
        : const Duration(minutes: 5);
    if (cutoff != null && now.difference(cutoff) < flushGap) {
      return;
    }
    _lastPulseFlush = now;
    final recent = [
      for (final sample in monitor.liveHistory)
        if (cutoff == null || sample.at.isAfter(cutoff)) sample,
    ];
    if (recent.isEmpty) {
      return;
    }
    final touched = await _pulseStore.merge(recent);
    PulseSync().push(touched);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _activitySampler.dispose();
    await _stopBackgroundHr();
    await _conn?.dispose();
    _conn = null;
  }

  /// Update the ongoing service notification with the latest value + trend.
  /// The user can hide the live value (Android still requires the ongoing
  /// notification, so it stays unchanged then). The toggle is read fresh so it
  /// takes effect without a service restart.
  Future<void> _updateNotification(int? mgdl, double? trendPerMin) async {
    // Drop repeats before touching prefs: `_handleUpdate` fires per protocol
    // update, so a backfill batch calls this dozens of times a second with the
    // SAME value — two SharedPreferences reads and an `updateService` each,
    // which is what makes Android shed the notification ("rate limit (5.0)
    // exceeded") and drops frames. Nothing changed → nothing to show.
    final signature = '$mgdl/$trendPerMin';
    if (signature == _shownNotification) {
      return;
    }
    _shownNotification = signature;
    final showValue = await ProfileLiveNotificationState().load();
    if (!showValue) {
      return;
    }
    if (mgdl == null) {
      return;
    }
    final profile = await ProfileGlucoseState.load();
    final arrow = trendPerMin != null
        ? ' ${_alarms?.trendArrow(trendPerMin) ?? ''}'
        : '';
    final String text = '${profile.formatWithUnit(mgdl)}$arrow';
    FlutterForegroundTask.updateService(
      notificationTitle: 'Insulink',
      notificationText: text,
    );
  }
}
