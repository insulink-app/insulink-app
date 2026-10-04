import 'dart:async';
import 'dart:math';

import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/demo/demo_glucose.dart';
import 'package:insulink/src/demo/demo_sensor.dart';

/// The demo sensor keeps delivering: a new reading every five minutes, written
/// to the store and announced to the UI with the same 'reading' and 'update'
/// messages the background service sends, so the headline, the charts and the
/// connection page move on exactly as they do with a real sensor.
///
/// The browser has no service isolate, so this runs in the page itself. Each
/// value continues the newest archived one along the slope of the demo curve
/// ([DemoGlucose.shapeAt]) with a little noise, so the line goes on without a
/// jump. A tab that was asleep catches up on every reading it missed.
class DemoLiveSensor {
  DemoLiveSensor({required this.onData});

  /// Receives the service messages (`CgmController`'s task-data handler).
  final void Function(Object data) onData;

  static const Duration checkEvery = Duration(seconds: 15);
  static const double noiseMgdl = 2.5;

  final Random _random = Random();
  late final DemoGlucose _shape = DemoGlucose(
    now: DateTime.now(),
    random: _random,
  );
  late final Future<CgmStore> _store = CgmStore.open();
  Timer? _timer;
  DateTime? _lastAt;
  int? _lastMgdl;
  bool _busy = false;

  void start() {
    _timer = Timer.periodic(checkEvery, (_) => unawaited(_catchUp()));
  }

  void stop() => _timer?.cancel();

  Future<void> _catchUp() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final store = await _store;
      _readNewest(store);
      while (_lastAt != null &&
          !_lastAt!.add(DemoGlucose.step).isAfter(DateTime.now())) {
        await _deliver(store, _lastAt!.add(DemoGlucose.step));
      }
    } finally {
      _busy = false;
    }
  }

  /// The newest archived reading, read once; afterwards this class knows it.
  void _readNewest(CgmStore store) {
    if (_lastAt != null) {
      return;
    }
    final now = DateTime.now();
    final recent = store.archiveRange(
      now.subtract(const Duration(hours: 1)),
      now,
    );
    if (recent.isEmpty) {
      return;
    }
    _lastAt = DateTime.fromMillisecondsSinceEpoch(recent.lastKey()! * 60000);
    _lastMgdl = recent[recent.lastKey()!];
  }

  Future<void> _deliver(CgmStore store, DateTime at) async {
    final previous = _lastMgdl!;
    final slope =
        _shape.shapeAt(at) - _shape.shapeAt(at.subtract(DemoGlucose.step));
    final noise = (_random.nextDouble() - 0.5) * 2 * noiseMgdl;
    final mgdl = (previous + slope + noise).round().clamp(48, 290);
    final trendTenths = ((mgdl - previous) / DemoGlucose.step.inMinutes * 10)
        .round();
    final start = store.loadSensorStart(DemoSensor.key) ?? at;
    final secs = at.difference(start).inSeconds;
    await store.archiveAddAll({at: mgdl});
    await store.saveLatest(
      DemoSensor.key,
      mgdl: mgdl,
      trendTenths: trendTenths,
      state: DemoSensor.stateOk,
      secsSinceStart: secs,
    );
    _lastAt = at;
    _lastMgdl = mgdl;
    onData({
      't': 'reading',
      'mgdl': mgdl,
      'trendTenths': trendTenths,
      'state': DemoSensor.stateOk,
      'secs': secs,
    });
    onData({'t': 'update'});
  }
}
