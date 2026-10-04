import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/demo/demo_glucose.dart';

/// A Dexcom G7 the demo pretends is paired and two days into its session, so
/// the overview shows its remaining life and treats the newest reading as
/// current instead of greying it out.
class DemoSensor {
  DemoSensor(this.glucose);

  final DemoGlucose glucose;

  static const String key = 'demo-g7';
  static const Duration age = Duration(days: 2, hours: 3);

  /// The G7's algorithm state for "sensor OK" (`device_info.dart`).
  static const int stateOk = 0x06;

  Future<void> pair() async {
    final store = await CgmStore.open();
    final start = glucose.end.subtract(age);
    await store.saveSensorType(SensorType.dexcomG7);
    await store.saveResolvedKey(key);
    await store.saveSensorStart(key, start);
    await store.saveLatest(
      key,
      mgdl: glucose.readings[glucose.end],
      trendTenths: (glucose.trendPerMinute * 10).round(),
      state: stateOk,
      secsSinceStart: glucose.end.difference(start).inSeconds,
    );
  }
}
