import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/chart_sync.dart';
import 'package:insulink/src/overview/chart/chart_x_axis.dart';

/// What the glucose chart and the insulin chart under it share so the pair
/// behaves as one graph.
void main() {
  late ChartSync sync;
  var notifications = 0;

  setUp(() {
    notifications = 0;
    sync = ChartSync()..addListener(() => notifications++);
  });

  tearDown(() => sync.dispose());

  test('nothing is known before the first window', () {
    expect(sync.hasWindow, isFalse);
    expect(sync.scrub, isNull);
  });

  test('a scrub reaches both charts', () {
    sync.setScrub(0.4);

    expect(sync.scrub, 0.4);
    expect(notifications, 1);
  });

  test('the same scrub again says nothing', () {
    sync.setScrub(0.4);
    sync.setScrub(0.4);

    expect(notifications, 1);
  });

  /// A finger that is half of a pinch is not pointing at anything. fl_chart
  /// keeps reporting touches through a two-finger gesture, so without this,
  /// zooming the glucose chart published a scrub and the insulin chart answered
  /// with a tooltip instead of zooming with it.
  test('a gesture suppresses scrubbing', () {
    sync.gesturing = true;

    sync.setScrub(0.4);

    expect(sync.scrub, isNull);
  });

  test('starting a gesture drops the readout already on screen', () {
    sync.setScrub(0.4, mirrored: true);

    sync.gesturing = true;

    expect(sync.scrub, isNull);
    expect(sync.scrubMirrored, isFalse);
  });

  test('scrubbing works again once the gesture ends', () {
    sync.gesturing = true;
    sync.setScrub(0.4);

    sync.gesturing = false;
    sync.setScrub(0.4);

    expect(sync.scrub, 0.4);
  });

  /// Clearing a scrub must never stay marked as mirrored: "nobody is pointing"
  /// has no owner, and a stale flag would make the chart above draw a readout
  /// for a scrub that no longer exists.
  test('clearing a scrub clears its owner', () {
    sync.setScrub(0.4, mirrored: true);

    sync.setScrub(null);

    expect(sync.scrubMirrored, isFalse);
  });

  test('a window reaches the chart below', () {
    final from = DateTime(2026, 5, 4, 8);
    final to = DateTime(2026, 5, 4, 20);

    sync.reportWindow(from: from, to: to, liveEdge: to, ticks: const []);

    expect(sync.hasWindow, isTrue);
    expect(sync.from, from);
    expect(notifications, 1);
  });

  /// Panning redraws the pair; a rebuild that lands on the same window must not,
  /// or the chart below rebuilds on every frame of the chart above.
  test('the same window again says nothing', () {
    final from = DateTime(2026, 5, 4, 8);
    final to = DateTime(2026, 5, 4, 20);

    sync.reportWindow(from: from, to: to, liveEdge: to, ticks: const []);
    sync.reportWindow(
      from: from,
      to: to,
      liveEdge: to,
      ticks: const [ChartTick(fraction: 0.5, label: '12')],
    );

    expect(notifications, 1);
    expect(sync.ticks, hasLength(1), reason: 'labels still adopted');
  });
}
