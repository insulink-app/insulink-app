import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/demo/demo_devices.dart';
import 'package:insulink/src/demo/demo_sensor.dart';

void main() {
  test('each earlier device ends where the next one starts', () {
    final now = DateTime(2026, 10, 4, 12);
    final devices = DemoDevices(now);
    final sensors = devices.sensors;
    final pods = devices.pumps;
    expect(sensors, hasLength(DemoDevices.sensorCount));
    expect(pods, hasLength(DemoDevices.podCount));
    expect(
      sensors.first['registered_at'],
      now
          .subtract(DemoSensor.age)
          .add(const Duration(minutes: 3))
          .millisecondsSinceEpoch,
    );
    expect(
      sensors.where((row) => row.containsKey('discarded_at')),
      hasLength(1),
    );
    expect(pods.where((row) => row.containsKey('discarded_at')), hasLength(1));
    final starts = [for (final row in pods) row['registered_at'] as int];
    expect(starts, [...starts]..sort((newer, older) => older.compareTo(newer)));
  });
}
