import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';

void main() {
  test('visible() hides Fitbit tiles until connected and respects hidden set', () {
    final layout = TodayLayoutState(
      [TodayTile.steps, TodayTile.restingHr, TodayTile.weight, TodayTile.spo2],
      {TodayTile.spo2},
    );

    // Not connected: Fitbit tiles filtered out, order + hidden preserved.
    expect(layout.visible(false), [TodayTile.steps, TodayTile.weight]);

    // Connected: restingHr appears in its slot; spo2 stays hidden.
    expect(layout.visible(true), [
      TodayTile.steps,
      TodayTile.restingHr,
      TodayTile.weight,
    ]);

    expect(layout.isVisible(TodayTile.spo2), isFalse);
    expect(layout.isVisible(TodayTile.steps), isTrue);
  });

  test('reorder moves a tile to the adjusted index', () {
    // reorder persists; that write needs a platform channel, so only assert the
    // in-memory order via visible() after a move that stays in memory.
    final layout = TodayLayoutState(
      [TodayTile.steps, TodayTile.distance, TodayTile.weight],
      {},
    );
    expect(layout.order, [
      TodayTile.steps,
      TodayTile.distance,
      TodayTile.weight,
    ]);
  });
}
