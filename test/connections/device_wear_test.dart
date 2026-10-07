import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/connections/history/device_record.dart';
import 'package:insulink/src/connections/history/device_wear_bar.dart';

DeviceHistoryEntry _sensor({required Duration worn, bool active = false}) {
  final start = DateTime(2026, 9, 1);
  return DeviceHistoryEntry(
    record: DeviceRecord(
      deviceKey: 'a',
      typeKey: 'sensor.type.g7',
      start: start,
      expiresAt: start.add(const Duration(days: 10, hours: 12)),
      registeredAt: start,
    ),
    endedAt: active ? null : start.add(worn),
  );
}

void main() {
  test('a sensor off before 90 % of its rated ten days came off early', () {
    final wear = DeviceWear(_sensor(worn: const Duration(days: 8)));
    expect(wear.fraction, closeTo(0.8, 1e-9));
    expect(wear.early, isTrue);
  });

  test('worn to the end, grace included, is full and not early', () {
    final wear = DeviceWear(_sensor(worn: const Duration(days: 10, hours: 12)));
    expect(wear.fraction, 1);
    expect(wear.early, isFalse);
  });

  test('a running sensor is never early', () {
    expect(DeviceWear(_sensor(worn: Duration.zero, active: true)).early, isFalse);
  });
}
