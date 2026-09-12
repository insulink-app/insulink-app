import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';

void main() {
  group('AlarmTone', () {
    test('every alarm has an existing asset in every style', () {
      for (final slot in AlarmSlot.values) {
        for (final tone in AlarmTone.values) {
          if (tone == AlarmTone.off) {
            continue;
          }
          final asset = File('assets/${tone.assetFor(slot)}');
          expect(asset.existsSync(), isTrue, reason: '${asset.path} missing');
        }
      }
    });

    test('off plays nothing, for every alarm', () {
      for (final slot in AlarmSlot.values) {
        expect(AlarmTone.off.assetFor(slot), isNull);
      }
    });

    test('the short styles are shorter than the classic tone', () {
      for (final slot in AlarmSlot.values) {
        final classic = File('assets/${AlarmTone.classic.assetFor(slot)}');
        for (final tone in [AlarmTone.short, AlarmTone.ping]) {
          final file = File('assets/${tone.assetFor(slot)}');
          expect(
            file.lengthSync(),
            lessThan(classic.lengthSync()),
            reason: '${file.path} is not shorter than ${classic.path}',
          );
        }
      }
    });

    test('every glucose alarm keeps its own tone within a style', () {
      final levels = [
        G7AlarmLevel.lowWarning,
        G7AlarmLevel.lowUrgent,
        G7AlarmLevel.highWarning,
        G7AlarmLevel.highUrgent,
      ];
      final assets = levels
          .map(
            (level) => AlarmTone.short.assetFor(G7AlarmManager.slotFor(level)),
          )
          .toSet();
      expect(assets.length, levels.length);
    });
  });
}
