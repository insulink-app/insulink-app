import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/loop/loop_cycle_badge.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The badge is the row's whole summary, so "above, below or level" has to be
/// read off the two rates correctly. Rates are stored to hundredths, so the
/// interesting case is the one just either side of a rounding artefact.
void main() {
  test('a rate above the schedule points up', () {
    expect(PodLoopCycleBadge.iconFor(1.25, 0.80), PhosphorIconsBold.arrowUp);
  });

  test('a rate below the schedule points down', () {
    expect(PodLoopCycleBadge.iconFor(0.30, 0.80), PhosphorIconsBold.arrowDown);
  });

  test('a suspended cycle points down, it is not level', () {
    expect(PodLoopCycleBadge.iconFor(0, 0.80), PhosphorIconsBold.arrowDown);
  });

  test('the schedule itself reads level', () {
    expect(PodLoopCycleBadge.iconFor(0.80, 0.80), PhosphorIconsBold.equals);
  });

  test('a difference under half a hundredth is a rounding artefact', () {
    expect(PodLoopCycleBadge.iconFor(0.802, 0.80), PhosphorIconsBold.equals);
    expect(PodLoopCycleBadge.iconFor(0.798, 0.80), PhosphorIconsBold.equals);
  });

  test('a whole hundredth apart is a decision', () {
    expect(PodLoopCycleBadge.iconFor(0.81, 0.80), PhosphorIconsBold.arrowUp);
  });

  test('a zero schedule with a rate on top still points up', () {
    expect(PodLoopCycleBadge.iconFor(0.45, 0), PhosphorIconsBold.arrowUp);
  });
}
