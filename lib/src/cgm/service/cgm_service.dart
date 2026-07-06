import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../profile/glucose/profile_glucose_state.dart';
import '../../profile/notifications/profile_live_notification_state.dart';
import '../../rust/frb_generated.dart';
import '../../sport/sport_store.dart';
import '../../sport/training/activity_recognition_sampler.dart';
import '../../sport/training/background_location_sampler.dart';
import '../../sport/training/cardio_detection_runner.dart';
import 'alarms.dart';
import '../cgm_connection.dart';
import '../event_sync.dart';
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

  /// The Rust J-PAKE core can be initialised exactly once per isolate; guard it
  /// so the watchdog's recovery re-init doesn't re-call `RustLib.init()` (which
  /// throws if already initialised).
  bool _coreReady = false;

  /// Piggybacks periodic GPS sampling on this already-running foreground service
  /// (flutter_foreground_task hosts only one), independent of the BLE pipeline.
  /// No-ops unless location is permitted — glucose reading never depends on it.
  final BackgroundLocationSampler _locationSampler =
      BackgroundLocationSampler();

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

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _locationTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _locationSampler.tick(),
    );
    _activitySampler.start();
    unawaited(const SportStore().applyTrainingDecisions());
    if (await _ensureReady()) {
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
    // Fall back to the standard G7 lifetime (10 days + 12 h grace) when the
    // sensor hasn't reported its own session length.
    final key = store.resolvedKey ?? _serial;
    final lifetime = _conn?.sessionLengthSec ?? 907200;
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
      'trendTenths': reading.trendTenths,
      'state': reading.state,
      'secs': reading.secsSinceStart,
    });
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
    _maybeDetectTraining();
    // Apply Confirm/Reject taps buffered by the notification-action isolate,
    // which can't reach secure storage itself (see SportStore.recordTrainingDecision).
    const SportStore().applyTrainingDecisions();
  }

  /// Runs cardio auto-detection at most every [_detectEvery]; each new training
  /// is added to the pending list and raises a confirm-notification.
  Future<void> _maybeDetectTraining() async {
    final last = _lastDetectionAt;
    if (last != null && DateTime.now().difference(last) < _detectEvery) {
      return;
    }
    _lastDetectionAt = DateTime.now();
    try {
      final result = await _detectionRunner.run(
        (training) async => _alarms?.notifyTrainingDetected(training),
      );
      _log(
        'cardio scan: ${result.logPoints} gps pts '
        '(${result.consideredPoints} new), ${result.detected} detected',
      );
    } catch (e) {
      _log('training detection error: $e');
    }
  }

  Future<void> _watchdog() async {
    try {
      // Recover a startup that threw before the pipeline existed.
      if (_conn == null) {
        if (await _ensureReady()) {
          _log('watchdog: pipeline rebuilt — connecting…');
          _startConnect();
        }
        return;
      }
      final connection = _conn!;

      // Warn the user once the link has been silent for 15 min while a sensor
      // is linked (best-effort; toggleable in profile notification settings).
      final last = _lastReadingAt;
      if (last != null) {
        _alarms?.checkConnectionLost(
          sensorLinked: _pairingCode.isNotEmpty,
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
            DateTime.now().difference(lastRestart) < _timing.processRestartAfter;
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
      if (last != null && DateTime.now().difference(last) > _timing.staleAfter) {
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

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _activitySampler.dispose();
    await _conn?.dispose();
    _conn = null;
  }

  /// Update the ongoing service notification with the latest value + trend.
  /// The user can hide the live value (Android still requires the ongoing
  /// notification, so it stays unchanged then). The toggle is read fresh so it
  /// takes effect without a service restart.
  Future<void> _updateNotification(int? mgdl, double? trendPerMin) async {
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
