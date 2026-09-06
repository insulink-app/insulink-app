import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/connections/status/connection_timeline.dart';

final _now = DateTime(2026, 3, 14, 12);
final _timeline = ConnectionTimeline(now: _now);

int _minutesAgo(int minutes) =>
    _now.subtract(Duration(minutes: minutes)).millisecondsSinceEpoch ~/ 60000;

/// The strip is the whole page: a bucket is "connected" when anything at all
/// arrived in it, and everything else is a gap. Getting the edges wrong would
/// draw an outage where there was none, which is the one thing it must not do.
void main() {
  test('a day of half-hour buckets', () {
    expect(_timeline.bucketCount, 48);
  });

  test('a single reading covers the bucket it falls in, and only that one', () {
    final covered = _timeline.cover([_minutesAgo(70)]);
    expect(covered.where((slice) => slice).length, 1);
    // 70 min ago is between 60 and 90, so the third bucket from the end.
    expect(covered[covered.length - 3], isTrue);
  });

  test('data older than the window is ignored, not clamped into it', () {
    expect(_timeline.cover([_minutesAgo(2000)]).contains(true), isFalse);
  });

  test('a reading from the future is ignored too', () {
    expect(_timeline.cover([_minutesAgo(-60)]).contains(true), isFalse);
  });

  test('a steady stream covers every bucket', () {
    final covered = _timeline.cover([
      for (var minute = 0; minute < 24 * 60; minute += 5) _minutesAgo(minute),
    ]);
    expect(covered.every((slice) => slice), isTrue);
    expect(ConnectionTimeline.outages(covered), 0);
  });

  test('a slice names the half hour it stands for', () {
    expect(_timeline.bucketStart(0), _now.subtract(const Duration(hours: 24)));
    expect(_timeline.bucketStart(47), _now.subtract(const Duration(minutes: 30)));
  });

  group('outages', () {
    test('counts stretches of silence, not silent buckets', () {
      expect(
        ConnectionTimeline.outages(const [true, false, false, false, true]),
        1,
      );
    });

    test('counts two separate gaps separately', () {
      expect(
        ConnectionTimeline.outages(const [true, false, true, false, true]),
        2,
      );
    });

    test('silence at the start of the window counts', () {
      expect(ConnectionTimeline.outages(const [false, false, true]), 1);
    });

    test('an unbroken strip has none', () {
      expect(ConnectionTimeline.outages(const [true, true, true]), 0);
    });
  });

  group('DeviceConnection', () {
    test('a device that never reported anything is not called broken', () {
      const device = DeviceConnection(
        labelKey: 'pump.label',
        icon: Icons.error,
        lastContact: null,
        covered: [false, false],
      );
      expect(device.isKnown, isFalse);
    });
  });
}
