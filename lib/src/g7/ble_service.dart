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
class G7TaskHandler extends TaskHandler {
  G7Connection? _conn;
  late G7AlarmManager _alarms;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Fresh isolate: the Rust J-PAKE core must be initialised here too.
    await RustLib.init();
    final notifications = FlutterLocalNotificationsPlugin();
    await G7AlarmManager.init(notifications);
    _alarms = G7AlarmManager(notifications);
    final store = await G7Store.open();
    final serial = store.serial ?? '';
    final code = store.pairingCode ?? '';

    _conn = G7Connection(
      store: store,
      serial: serial,
      pairingCode: code,
      onLog: (line) => FlutterForegroundTask.sendDataToMain({
        't': 'log',
        'line': line,
      }),
      onReading: (r) {
        _updateNotification(r.glucoseMgDl);
        if (r.glucoseMgDl != null) {
          _alarms.check(r.glucoseMgDl, r.trendMgDlPerMin);
        }
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

    await _conn!.connect();
  }

  /// Watchdog: if the link dropped (and we're not mid-connect), try again. The
  /// cadence is set by `ForegroundTaskOptions.eventAction` in the UI.
  @override
  void onRepeatEvent(DateTime timestamp) {
    final c = _conn;
    if (c != null && !c.isConnected && !c.isConnecting) {
      FlutterForegroundTask.sendDataToMain({
        't': 'log',
        'line': 'watchdog: reconnecting…',
      });
      c.connect();
    }
  }

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
