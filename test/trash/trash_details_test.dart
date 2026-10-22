import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/trash/trash_details.dart';
import 'package:insulink/src/trash/trash_entry.dart';

void main() {
  test('a meal lists its amounts and food names, skipping missing ones', () {
    const entry = TrashEntry(
      kind: TrashKind.meal,
      deletedAtMs: 0,
      data: {
        'time': 0,
        'carbs': 40,
        'bolus': 2,
        'entries': [
          {'name': 'Bread'},
          {'name': 'Jam'},
        ],
      },
    );
    final rows = Map.fromEntries(
      TrashDetails(entry).rows.map((row) => MapEntry(row.$1, row.$2)),
    );
    expect(rows['trash.detail.carbs'], '40 g');
    expect(rows['trash.detail.foods'], 'Bread, Jam');
    expect(rows.containsKey('trash.detail.glucose'), isFalse);
  });

  test('a cardio training shows distance and duration', () {
    const entry = TrashEntry(
      kind: TrashKind.cardio,
      deletedAtMs: 0,
      data: {'start': 0, 'end': 1800000, 'dist': 5000},
    );
    final values = TrashDetails(entry).rows.map((row) => row.$2).toList();
    expect(values, contains('30 min'));
    expect(values.first, endsWith('km'));
  });
}
