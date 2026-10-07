import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

void main() {
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  test('both themes carry the tokens they are built from', () {
    expect(AppTheme.light.extension<InsulinkColors>(), InsulinkColors.light);
    expect(AppTheme.dark.extension<InsulinkColors>(), InsulinkColors.dark);
  });

  test('scheme and glucose palette are fed from the tokens', () {
    for (final entry in themes.entries) {
      final tokens = entry.value.extension<InsulinkColors>()!;
      final glucose = entry.value.extension<GlucoseColors>()!;
      expect(entry.value.colorScheme.primary, tokens.accent, reason: entry.key);
      expect(
        entry.value.colorScheme.onPrimary,
        tokens.onAccent,
        reason: entry.key,
      );
      expect(
        entry.value.scaffoldBackgroundColor,
        tokens.ground,
        reason: entry.key,
      );
      expect(glucose.low, tokens.low, reason: entry.key);
    }
  });

  test('lerp at t=0 / t=1 returns the endpoints', () {
    const from = InsulinkColors.light;
    const to = InsulinkColors.dark;
    expect(from.lerp(to, 0).ground, from.ground);
    expect(from.lerp(to, 1).accent, to.accent);
    expect(from.lerp(null, 0.5), same(from));
  });
}
