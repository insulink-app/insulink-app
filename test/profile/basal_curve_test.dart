import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';

void main() {
  // regenerate() is pure (no storage), so it runs without binding init.
  BasalProfile shaped(List<BasalPeak> peaks, double total) {
    final profile = BasalProfile.initial('t')
      ..dailyTotal = total
      ..peaks.clear()
      ..peaks.addAll(peaks);
    profile.regenerate();
    return profile;
  }

  test('curve roughly sums to the requested daily total', () {
    // Rounding to 0.05 U/h across 24 bars leaves only a small drift.
    expect(shaped([BasalPeak(5, 1.0)], 24).total, closeTo(24, 1.0));
  });

  test('a peak lifts its hour above the opposite side', () {
    final rates = shaped([BasalPeak(5, 1.5)], 24).rates;
    expect(rates[5], greaterThan(rates[17]));
  });

  test('wraps around midnight', () {
    final rates = shaped([BasalPeak(0, 1.5)], 24).rates;
    expect(rates[23], greaterThan(rates[12]));
  });

  test('every rate snaps to the 0.05 U/h grid', () {
    final rates = shaped([BasalPeak(8, 1.0), BasalPeak(20, 0.8)], 30).rates;
    for (final rate in rates) {
      expect((rate / BasalProfile.step).roundToDouble(),
          closeTo(rate / BasalProfile.step, 1e-9));
    }
  });

  test('round-trips through JSON', () {
    final profile = shaped([BasalPeak(6, 1.2)], 28);
    final restored = BasalProfile.fromJson(profile.toJson());
    expect(restored.name, profile.name);
    expect(restored.rates, profile.rates);
    expect(restored.dailyTotal, 28);
    expect(restored.peaks.single.hour, 6);
  });
}
