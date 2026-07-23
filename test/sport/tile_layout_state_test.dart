import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/activity/today_layout.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;

  setUp(() {
    backing = installSecureStorageMock();
  });

  test('parsing nothing yields every tile in declaration order', () {
    final parsed = TileLayoutState.parse(null, TodayTile.values, {
      TodayTile.spo2,
    });

    expect(parsed.order, TodayTile.values);
    expect(parsed.hidden, {TodayTile.spo2});
  });

  test('parsing appends tiles a stored older layout does not know', () {
    final raw = TileLayoutState.encode(const [
      TodayTile.weight,
      TodayTile.steps,
    ], const {TodayTile.steps});

    final parsed = TileLayoutState.parse(raw, TodayTile.values, {
      TodayTile.spo2,
    });

    expect(parsed.order.take(2), [TodayTile.weight, TodayTile.steps]);
    expect(parsed.order.toSet(), TodayTile.values.toSet());
    expect(parsed.hidden, {TodayTile.steps, TodayTile.spo2});
  });

  test('an unknown tile name in the blob is dropped, not crashed on', () {
    final raw = jsonEncode({
      'order': ['weight', 'from_a_newer_version'],
      'hidden': ['also_unknown'],
    });

    final parsed = TileLayoutState.parse(raw, TodayTile.values, const <TodayTile>{});

    expect(parsed.order.first, TodayTile.weight);
    expect(parsed.order.length, TodayTile.values.length);
    expect(parsed.hidden, isEmpty);
  });

  test('a blob with non-list members parses as an empty layout, then refilled', () {
    final parsed = TileLayoutState.parse(
      jsonEncode({'order': 'broken'}),
      TodayTile.values,
      {TodayTile.spo2},
    );

    expect(parsed.order.toSet(), TodayTile.values.toSet());
    expect(parsed.hidden, {TodayTile.spo2});
  });

  test('setVisible flips the tile and persists the layout', () async {
    final layout = TodayLayoutState(TodayTile.values.toList(), {
      TodayTile.spo2,
    });

    await layout.setVisible(TodayTile.spo2, true);
    expect(layout.isVisible(TodayTile.spo2), isTrue);

    await layout.setVisible(TodayTile.steps, false);
    expect(layout.isVisible(TodayTile.steps), isFalse);

    final stored =
        jsonDecode(backing[TodayLayoutState.key]!) as Map<String, dynamic>;
    expect(stored['hidden'], ['steps']);
  });

  test('reorder moves a tile to the adjusted index and persists', () async {
    final layout = TodayLayoutState([
      TodayTile.steps,
      TodayTile.distance,
      TodayTile.weight,
    ], {});

    await layout.reorder(0, 2);

    expect(layout.order, [
      TodayTile.distance,
      TodayTile.weight,
      TodayTile.steps,
    ]);
    final stored =
        jsonDecode(backing[TodayLayoutState.key]!) as Map<String, dynamic>;
    expect(stored['order'], ['distance', 'weight', 'steps']);
  });

  test('moveTile drops the tile just before the target', () async {
    final layout = TodayLayoutState([
      TodayTile.steps,
      TodayTile.distance,
      TodayTile.weight,
    ], {});

    await layout.moveTile(TodayTile.weight, TodayTile.distance);
    expect(layout.order, [
      TodayTile.steps,
      TodayTile.weight,
      TodayTile.distance,
    ]);

    await layout.moveTile(TodayTile.steps, TodayTile.steps);
    expect(layout.order.first, TodayTile.steps);
  });

  test('load falls back to the defaults, then reads back what was saved', () async {
    final fresh = await TodayLayoutState.load();
    expect(fresh.order, TodayTile.values);
    expect(fresh.isVisible(TodayTile.spo2), isFalse);

    await fresh.setVisible(TodayTile.spo2, true);

    final reloaded = await TodayLayoutState.load();
    expect(reloaded.isVisible(TodayTile.spo2), isTrue);
  });

  test('the raw blob for the settings sync defaults before anything is saved', () async {
    expect(
      await TodayLayoutState.loadRaw(),
      TileLayoutState.encode(TodayTile.values, const {TodayTile.spo2}),
    );

    backing[TodayLayoutState.key] = 'stored';
    expect(await TodayLayoutState.loadRaw(), 'stored');
  });

  test('order is unmodifiable so the grid cannot mutate it behind the state', () {
    final layout = TodayLayoutState(TodayTile.values.toList(), {});

    expect(() => layout.order.add(TodayTile.steps), throwsUnsupportedError);
  });
}
