import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/insulin_colors.dart';

/// Relative luminance, for the contrast checks below.
double _luminance(Color color) => color.computeLuminance();

double _contrast(Color first, Color second) {
  final lighter = _luminance(first) > _luminance(second) ? first : second;
  final darker = identical(lighter, first) ? second : first;
  return (_luminance(lighter) + 0.05) / (_luminance(darker) + 0.05);
}

void main() {
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  /// A role set in one theme and not the other does not fall back sensibly, it
  /// throws. Both lists have to move together.
  test('both themes define the insulin colours', () {
    for (final entry in themes.entries) {
      expect(entry.value.extension<InsulinColors>(), isNotNull,
          reason: '${entry.key} is missing InsulinColors');
    }
  });

  group('the two kinds can be told apart', () {
    /// The whole point of the chart is the distinction. Two indigos a shade
    /// apart would draw one bar chart in one colour.
    test('basal and bolus are far enough apart to read', () {
      for (final entry in themes.entries) {
        final colors = entry.value.extension<InsulinColors>()!;

        expect(_contrast(colors.basal, colors.bolus), greaterThan(1.6),
            reason: '${entry.key}: basal and bolus are too close');
      }
    });

    test('both stand out from the surface they are drawn on', () {
      for (final entry in themes.entries) {
        final colors = entry.value.extension<InsulinColors>()!;
        final surface = entry.value.colorScheme.surface;

        expect(_contrast(colors.basal, surface), greaterThan(2.0),
            reason: '${entry.key}: basal disappears into the surface');
        expect(_contrast(colors.bolus, surface), greaterThan(2.0),
            reason: '${entry.key}: bolus disappears into the surface');
      }
    });
  });

  /// Glucose is its own language and must not move when insulin does. Sharing a
  /// value would tie the two together and make a chart of one read as the other.
  test('insulin borrows nothing from the glucose palette', () {
    for (final entry in themes.entries) {
      final insulin = entry.value.extension<InsulinColors>()!;
      final glucose = entry.value.extension<GlucoseColors>()!;
      final glucoseTones = {
        glucose.low,
        glucose.inRange,
        glucose.high,
      };

      expect(glucoseTones.contains(insulin.basal), isFalse,
          reason: '${entry.key}: basal is a glucose colour');
      expect(glucoseTones.contains(insulin.bolus), isFalse,
          reason: '${entry.key}: bolus is a glucose colour');
    }
  });
}
