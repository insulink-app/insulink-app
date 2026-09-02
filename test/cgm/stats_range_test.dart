import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';

/// The analysis range selector drives the forecast evaluation, which asks the
/// backend for an absolute window. These are the two shapes that window comes in.
void main() {
  test('a preset window ends now and reaches its duration back', () {
    final controller = CgmController();
    controller.statsPreset = const Duration(days: 7);
    final range = controller.statsRange;
    final span = range.to.difference(range.from);
    expect(span.inHours, 7 * 24);
    expect(
      DateTime.now().difference(range.to).inSeconds.abs() < 5,
      isTrue,
    );
  });

  test('a custom range is handed over exactly as picked', () {
    final controller = CgmController();
    final from = DateTime(2026, 3, 1);
    final to = DateTime(2026, 3, 15);
    controller.setStatsCustomRange(from, to);
    expect(controller.statsRange.from, from);
    expect(controller.statsRange.to, to);
  });
}
