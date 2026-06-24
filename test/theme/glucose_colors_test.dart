import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

void main() {
  group('GlucoseColors', () {
    test('copyWith overrides only the given fields', () {
      const base = GlucoseColors.standard;
      final changed = base.copyWith(low: const Color(0xFF000000));
      expect(changed.low, const Color(0xFF000000));
      expect(changed.inRange, base.inRange);
      expect(changed.high, base.high);
    });

    test('lerp at t=0 / t=1 returns the endpoints', () {
      const a = GlucoseColors.headlineLight;
      const b = GlucoseColors.headlineDark;
      expect(a.lerp(b, 0).inRange, a.inRange);
      expect(a.lerp(b, 1).inRange, b.inRange);
    });

    test('lerp blends the channels midway', () {
      const a = GlucoseColors.headlineLight;
      const b = GlucoseColors.headlineDark;
      final mid = a.lerp(b, 0.5);
      expect(mid.low, Color.lerp(a.low, b.low, 0.5));
    });

    test('lerp against a non-GlucoseColors falls back to this', () {
      const a = GlucoseColors.standard;
      expect(a.lerp(null, 0.5), same(a));
    });
  });
}
