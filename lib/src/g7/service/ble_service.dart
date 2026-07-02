import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../profile/glucose/profile_glucose_state.dart';
import '../../profile/notifications/profile_live_notification_state.dart';
import '../../rust/frb_generated.dart';
import '../../sport/training/background_location_sampler.dart';
import 'alarms.dart';
import 'service_log.dart';
import '../event_sync.dart';
import '../glucose_sync.dart';
import '../protocol/connection.dart';
import '../sensor_sync.dart';
import '../store.dart';

/// Entry point for the foreground-service isolate. Must be a top-level function
/// annotated `vm:entry-point` so it survives tree-shaking and can be invoked by
/// the native service after the UI/activity (and its isolate) are gone.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(G7TaskHandler());
}

/// Hosts the [G7Connection] inside the Android foreground service. This isolate
/// keeps the BLE link and the read pipeline alive while the app is backgrounded
/// or fully closed, persisting glucose to [G7Store] and pushing live updates
/// back to the UI over the foreground-task data channel.
///
/// Robustness is the whole point of this class: the isolate must survive a
/// failed startup, a wedged connect, a half-open BLE link, and a BLE stack that
/// stops delivering — without a UI around to notice. The [onRepeatEvent]
/// watchdog (cadence from `ForegroundTaskOptions.eventAction`) is the only thing
/// that runs while the phone is asleep, so it owns every recovery path.
class G7TaskHandler extends TaskHandler {
  G7Connection? _conn;
  G7AlarmManager? _alarms;
  G7Store? _store;
  String _serial = '';
  String _pairingCode = '';

  /// The Rust J-PAKE core can be initialised exactly once per isolate; guard it
  /// so the watchdog's recovery re-init doesn't re-call `RustLib.init()` (which
  /// throws if already initialised).
  bool _coreReady = false;

  /// Durable log so the watchdog's overnight recovery activity survives a
  /// process/isolate restart and is readable in the UI afterwards.
  final ServiceLog _serviceLog = ServiceLog();

  /// Piggybacks periodic GPS sampling on this already-running foreground service
  /// (flutter_foreground_task hosts only one), independent of the BLE pipeline.
  /// No-ops unless location is permitted — glucose reading never depends on it.
  final BackgroundLocationSampler _locationSampler =
      BackgroundLocationSampler();

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

  /// No reading for this long while "connected" ⇒ half-open link ⇒ force a clean
  /// reconnect.
  static const _staleAfter = Duration(minutes: 12);

  /// No reading for this long at all ⇒ the in-process BLE stack is likely wedged
  /// ⇒ restart the service (fresh isolate + Rust core), and if THAT already
  /// failed, the whole process (the only thing that resets a wedged native BLE
  /// scanner on Android 13+).
  static const _restartAfter = Duration(minutes: 25);

  /// If a `restartService()` happened within this window and data is STILL
  /// absent, the isolate wasn't the problem — the native BLE scanner is wedged
  /// (the Pixel/Android-13+ "scanner silently stops returning results" failure;
  /// a Bluetooth toggle would clear it but `turnOff()` is a no-op on 13+). Only
  /// a full process restart resets it. Generous enough to span the ~25-min gap a
  /// fresh isolate runs before it would re-trip [_restartAfter].
  static const _processRestartAfter = Duration(minutes: 35);

  /// A single `connect()` should resolve well within this; if it doesn't,
  /// force-reset so it can't pin the watchdog. Sized for the autoConnect
  /// reconnect path: after we arm autoConnect, the OS reconnects only when the
  /// G7 next advertises — up to one ~5-min delivery cycle away — so a wait that
  /// long is NORMAL, not a wedge. `connectAndBind` self-bounds the wait at 6 min;
  /// this backstop sits just past that so it only fires on a genuinely pinned
  /// attempt. (The scan path resolves far quicker, so the looser bound is free.)
  static const _connectStuckAfter = Duration(minutes: 7);

  /// After a successful reading the G7 won't advertise again for ~5 min, so
  /// scanning in the minutes right after one is pure wasted radio — and that
  /// near-continuous scanning ran THIS app's Android BLE scan "Score" to ~40×
  /// any other app on the device (dumpsys). Hold the watchdog's reconnect off
  /// this long after a delivery. Kept well under the ~5-min delivery interval so
  /// clock drift can't make us miss the next advertisement; a MISSED delivery
  /// leaves [_lastDeliveryAt] old, so we resume scanning normally.
  static const _reconnectBackoff = Duration(minutes: 3);

  /// Wall-clock of the last actual EGV delivery (null until the first), used
  /// only for [_reconnectBackoff]. Distinct from [_lastReadingAt], which is
  /// SEEDED at startup for the restart escalation — seeding this one would
  /// wrongly suppress the very first connect.
  DateTime? _lastDeliveryAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _locationTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _locationSampler.tick(),
    );
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
        final store = await G7Store.open();
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

  void _buildConnection() {
    final store = _store!;
    final alarms = _alarms!;
    final serial = _serial;
    _conn = G7Connection(
      store: store,
      serial: serial,
      pairingCode: _pairingCode,
      onLog: _log,
      onReading: (reading) {
        // A reading means the link is healthy — reset the health clock and
        // clear any pending "connection lost" warning.
        _lastReadingAt = DateTime.now();
        _lastDeliveryAt = _lastReadingAt;
        alarms.onReading();
        _updateNotification(reading.glucoseMgDl, reading.trendMgDlPerMin);
        if (reading.glucoseMgDl != null) {
          alarms.check(reading.glucoseMgDl, reading.trendMgDlPerMin);
        }
        // Mirror the paired sensor to the account (best-effort; only POSTs on a
        // fresh pair or when the identity changed).
        SensorSync().sync(store);
        // One-shot warning when the sensor has < 24 h of session left. The
        // sensor's reported session length is best-effort; fall back to the
        // standard G7 lifetime (10 days + 12 h grace) when it's unknown.
        alarms.checkExpiry(
          store: store,
          key: store.resolvedKey ?? serial,
          sessionLengthSec: _conn?.sessionLengthSec ?? 907200,
          secsSinceStart: reading.secsSinceStart,
        );
        FlutterForegroundTask.sendDataToMain({
          't': 'reading',
          'mgdl': reading.glucoseMgDl,
          'trendTenths': reading.trendTenths,
          'state': reading.state,
          'secs': reading.secsSinceStart,
        });
      },
      onUpdate: () {
        _updateNotification(_conn?.latestMgDl, _conn?.latestTrendPerMin);
        FlutterForegroundTask.sendDataToMain({'t': 'update'});
      },
      onConnectionState: (connected) => FlutterForegroundTask.sendDataToMain({
        't': 'conn',
        'connected': connected,
      }),
      onArchive: (readings) {
        GlucoseSync().queue(readings, _log);
        // Flush any service-isolate events (alarm zones, signal loss, new
        // sensor) to the backend; retries on the next reading if it fails.
        EventSync().sync(store, _log);
      },
    );
  }

  /// Watchdog: the only code that runs while the phone is asleep. Drives every
  /// recovery path — rebuild a failed startup, reconnect a dropped link, reset a
  /// wedged connect, drop a half-open link, and restart the whole service if the
  /// BLE stack has stopped delivering. Cadence: `eventAction` in the UI.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _watchdog();
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
          DateTime.now().difference(last) > _restartAfter) {
        _restarting = true;
        final lastRestart = _store?.lastServiceRestartAt;
        final restartedRecently =
            lastRestart != null &&
            DateTime.now().difference(lastRestart) < _processRestartAfter;
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
            DateTime.now().difference(since) > _connectStuckAfter) {
          _log('watchdog: connect wedged — resetting');
          await connection.dispose();
        }
        return;
      }

      // The G7 drops the link after each ~5-min delivery, so "not connected" is
      // the NORMAL resting state — reconnect to catch the next delivery. Hold off
      // for [_reconnectBackoff] after a delivery on BOTH paths: the sensor won't
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
            DateTime.now().difference(delivered) < _reconnectBackoff) {
          return;
        }
        _log('watchdog: reconnecting…');
        _startConnect();
        return;
      }

      // Connected but silent past the stale window ⇒ a half-open link that will
      // never deliver — drop it so the next tick reconnects cleanly.
      if (last != null && DateTime.now().difference(last) > _staleAfter) {
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
    _serviceLog.append(line);
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
