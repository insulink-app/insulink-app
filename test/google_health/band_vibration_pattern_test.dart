import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/google_health/band/band_vibration_pattern.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';

/// Every alarm must feel different on the wrist, coded like the tones:
/// double pulse = low, single = high, groups = severity.
void main() {
  test('no two alarms share a vibration pattern', () {
    final patterns = {for (final slot in AlarmSlot.values) (slot.doublePulse, slot.pulseGroups)};
    expect(patterns.length, AlarmSlot.values.length);
  });

  test('low is a double pulse, high a single one', () {
    expect(AlarmSlot.lowUrgent.doublePulse, isTrue);
    expect(AlarmSlot.advisoryLow.doublePulse, isTrue);
    expect(AlarmSlot.highWarning.doublePulse, isFalse);
  });

  test('pre-warning once, warning twice, urgent three times', () {
    expect(AlarmSlot.advisoryHigh.pulseGroups, 1);
    expect(AlarmSlot.lowWarning.pulseGroups, 2);
    expect(AlarmSlot.highUrgent.pulseGroups, 3);
  });

  test('each alarm has its own switch', () {
    final keys = {for (final slot in AlarmSlot.values) slot.bandSetting.storageKey};
    expect(keys.length, AlarmSlot.values.length);
  });
}
