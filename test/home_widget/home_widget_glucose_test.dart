import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/home_widget/home_widget_glucose.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';

ProfileGlucoseState profile(GlucoseUnit unit) => ProfileGlucoseState(
  unit: unit,
  targetLow: 70,
  targetHigh: 180,
  urgentLow: 55,
  low: 70,
  high: 180,
  urgentHigh: 250,
);

/// Installs a fake native side and returns the arguments of the last push.
Map<Object?, Object?>? Function() capturePushes({bool fail = false}) {
  Map<Object?, Object?>? last;
  const channel = MethodChannel('insulink/glucose_widget');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (fail) {
          throw PlatformException(code: 'no_widget');
        }
        last = call.arguments as Map<Object?, Object?>;
        return null;
      });
  return () => last;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeWidgetGlucose.publish', () {
    test('sends the value in the chosen unit', () async {
      final pushed = capturePushes();
      await HomeWidgetGlucose().publish(
        profile: profile(GlucoseUnit.mmol),
        mgdl: 120,
        arrow: '↗',
      );
      expect(pushed()?['value'], '6.7');
      expect(pushed()?['unit'], 'mmol/L');
      expect(pushed()?['arrow'], '↗');
    });

    test('colours the value by the target range, not by the alarm zone',
        () async {
      final pushed = capturePushes();
      final glucose = profile(GlucoseUnit.mgdl);
      await HomeWidgetGlucose().publish(
        profile: glucose,
        mgdl: 120,
        arrow: '→',
      );
      expect(pushed()?['color'], GlucoseColors.standard.inRange.toARGB32());
      await HomeWidgetGlucose().publish(profile: glucose, mgdl: 65, arrow: '↓');
      expect(pushed()?['color'], GlucoseColors.standard.low.toARGB32());
      await HomeWidgetGlucose().publish(profile: glucose, mgdl: 240, arrow: '↑');
      expect(pushed()?['color'], GlucoseColors.standard.high.toARGB32());
    });

    test('stamps the push so the widget can age the value', () async {
      final pushed = capturePushes();
      final before = DateTime.now().millisecondsSinceEpoch;
      await HomeWidgetGlucose().publish(
        profile: profile(GlucoseUnit.mgdl),
        mgdl: 120,
        arrow: '→',
      );
      expect(pushed()?['time'], greaterThanOrEqualTo(before));
    });

    test('a missing widget does not fail the reading', () async {
      capturePushes(fail: true);
      await expectLater(
        HomeWidgetGlucose().publish(
          profile: profile(GlucoseUnit.mgdl),
          mgdl: 120,
          arrow: '→',
        ),
        completes,
      );
    });
  });
}
