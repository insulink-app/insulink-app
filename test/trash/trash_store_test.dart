import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/trash/trash_entry.dart';
import 'package:insulink/src/trash/trash_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final meal = Meal(
    time: DateTime(2026, 10, 20, 12, 30),
    carbs: 45,
    glucoseMgdl: 120,
    bolus: 3,
    entries: const [],
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a kept meal comes back whole and leaves on take', () async {
    const store = TrashStore();
    await store.keep(TrashKind.meal, meal.toJson());
    final kept = (await store.load()).single;
    expect(kept.kind, TrashKind.meal);
    expect(kept.time, meal.time);
    expect(Meal.fromJson(kept.data).carbs, 45);
    await store.take(kept);
    expect(await store.load(), isEmpty);
  });

  test('entries older than 30 days are purged', () async {
    final old = TrashEntry(
      kind: TrashKind.meal,
      deletedAtMs: DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch,
      data: meal.toJson(),
    );
    FlutterSecureStorage.setMockInitialValues({
      'trash.entries': jsonEncode([old.toJson()]),
    });
    expect(await const TrashStore().load(), isEmpty);
  });

  test('a routine without a time of its own shows when it was deleted', () {
    const routine = TrashEntry(
      kind: TrashKind.routine,
      deletedAtMs: 1000000000000,
      data: {'id': 'r1', 'name': 'Push', 'items': []},
    );
    expect(routine.summary, 'Push');
    expect(routine.time.millisecondsSinceEpoch, 1000000000000);
  });
}
