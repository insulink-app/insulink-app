import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/connections/history/device_record.dart';

DateTime _at(int day, {int hour = 0}) => DateTime(2026, 3, day, hour);

DeviceRecord _sensor(
  String key,
  int startDay, {
  int lifeDays = 10,
  DateTime? discardedAt,
  DateTime? registeredAt,
}) {
  return DeviceRecord(
    deviceKey: key,
    typeKey: 'sensor.type.g7',
    start: _at(startDay),
    expiresAt: _at(startDay + lifeDays),
    registeredAt: registeredAt ?? _at(startDay),
    discardedAt: discardedAt,
  );
}

/// The history's whole job is deciding when a device came off, because no record
/// says so: a sensor swapped out on day three keeps its full ten-day expiry.
void main() {
  test('a device that ran out ends at its expiry', () {
    final history = DeviceHistory([_sensor('a', 1)], now: _at(20));
    final entry = history.resolve().single;
    expect(entry.isActive, isFalse);
    expect(entry.endedAt, _at(11));
    expect(entry.worn().inDays, 10);
    expect(entry.ratedDays, 10);
  });

  test('a successor ends the one before it, however much expiry was left', () {
    final history = DeviceHistory(
      [_sensor('a', 1), _sensor('b', 4)],
      now: _at(6),
    );
    final entries = history.resolve();
    expect(entries.first.start, _at(4));
    expect(entries.last.endedAt, _at(4));
    expect(entries.last.worn().inDays, 3);
    expect(entries.first.isActive, isTrue);
  });

  test('a discarded device ends when the user said so', () {
    final history = DeviceHistory(
      [_sensor('a', 1, discardedAt: _at(3, hour: 12))],
      now: _at(5),
    );
    final entry = history.resolve().single;
    expect(entry.wasDiscarded, isTrue);
    expect(entry.endedAt, _at(3, hour: 12));
  });

  test('the running device has no end and is worn up to now', () {
    final history = DeviceHistory([_sensor('a', 1)], now: _at(4));
    final entry = history.resolve().single;
    expect(entry.isActive, isTrue);
    expect(entry.endedAt, isNull);
    expect(entry.worn(now: _at(4)).inDays, 3);
  });

  test('a re-registered device is one row, keeping the first registration', () {
    final history = DeviceHistory([
      _sensor('a', 1, registeredAt: _at(1)),
      _sensor('a', 1, registeredAt: _at(3)),
    ], now: _at(4));
    final entries = history.resolve();
    expect(entries, hasLength(1));
    expect(entries.single.record.registeredAt, _at(1));
  });
}
