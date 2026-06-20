import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../rust/frb_generated.dart';
import 'alarms.dart';
import 'connection.dart';
import 'store.dart';

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
  /// ⇒ restart the whole service (fresh isolate + Rust core + BLE stack).
  static const _restartAfter = Duration(minutes: 25);

  /// A single `connect()` should resolve well within this (the transport bounds
  /// every step); if it doesn't, force-reset so it can't pin the watchdog.
  static const _connectStuckAfter = Duration(minutes: 3);

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
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
    if (_conn != null) return true;
    try {
      if (!_coreReady) {
        // Fresh isolate: the Rust J-PAKE core must be initialised here too.
        await RustLib.init();
        _coreReady = true;
      }
      if (_store == null) {
        final notifications = FlutterLocalNotificationsPlugin();
        await G7AlarmManager.init(notifications);
        _alarms = G7AlarmManager(notifications);
        final store = await G7Store.open();
        _store = store;
        _serial = store.serial ?? '';
        _pairingCode = store.pairingCode ?? '';
      }
      _buildConnection();
      // Seed the health clock so a service that never gets a first reading still
      // escalates to a restart instead of retrying silently forever.
      _lastReadingAt ??= DateTime.now();
      return true;
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({
        't': 'log',
        'line': 'service init error: $e',
      });
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
      onLog: (line) =>
          FlutterForegroundTask.sendDataToMain({'t': 'log', 'line': line}),
      onReading: (r) {
        // A reading means the link is healthy — reset the health clock.
        _lastReadingAt = DateTime.now();
        _updateNotification(r.glucoseMgDl);
        if (r.glucoseMgDl != null) {
          alarms.check(r.glucoseMgDl, r.trendMgDlPerMin);
        }
        // One-shot warning when the sensor has < 24 h of session left. The
        // sensor's reported session length is best-effort; fall back to the
        // standard G7 lifetime (10 days + 12 h grace) when it's unknown.
        alarms.checkExpiry(
          store: store,
          key: store.resolvedKey ?? serial,
          sessionLengthSec: _conn?.sessionLengthSec ?? 907200,
          secsSinceStart: r.secsSinceStart,
        );
        FlutterForegroundTask.sendDataToMain({
          't': 'reading',
          'mgdl': r.glucoseMgDl,
          'trendTenths': r.trendTenths,
          'state': r.state,
          'secs': r.secsSinceStart,
        });
      },
      onUpdate: () {
        _updateNotification(_conn?.latestMgDl);
        FlutterForegroundTask.sendDataToMain({'t': 'update'});
      },
      onConnectionState: (connected) => FlutterForegroundTask.sendDataToMain({
        't': 'conn',
        'connected': connected,
      }),
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
      final c = _conn!;

      // Last resort: no data for far too long ⇒ the in-process BLE stack is
      // likely wedged (reconnect attempts can't clear it). Restart the whole
      // service for a clean isolate + Rust core + BLE stack.
      final last = _lastReadingAt;
      if (!_restarting &&
          last != null &&
          DateTime.now().difference(last) > _restartAfter) {
        _log('watchdog: no data for too long — restarting service');
        _restarting = true;
        await FlutterForegroundTask.restartService();
        return;
      }

      // A wedged connect: the transport bounds each step, but force-reset if the
      // attempt still exceeds the cap so it can't pin the watchdog forever.
      if (c.isConnecting) {
        final since = _connectStartedAt;
        if (since != null &&
            DateTime.now().difference(since) > _connectStuckAfter) {
          _log('watchdog: connect wedged — resetting');
          await c.dispose();
        }
        return;
      }

      // The G7 drops the link after each ~5-min delivery, so "not connected" is
      // the NORMAL resting state — scan + reconnect to catch the next delivery.
      if (!c.isConnected) {
        _log('watchdog: reconnecting…');
        _startConnect();
        return;
      }

      // Connected but silent past the stale window ⇒ a half-open link that will
      // never deliver — drop it so the next tick reconnects cleanly.
      if (last != null && DateTime.now().difference(last) > _staleAfter) {
        _log('watchdog: link stale — forcing reconnect');
        await c.dispose();
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

  void _log(String line) =>
      FlutterForegroundTask.sendDataToMain({'t': 'log', 'line': line});

  @override
  void onReceiveData(Object data) {
    if (data == 'disconnect') {
      _conn?.dispose();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _conn?.dispose();
    _conn = null;
  }

  void _updateNotification(int? mgdl) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Insulink',
      notificationText: mgdl != null ? '$mgdl mg/dL' : 'connecting…',
    );
  }
}
