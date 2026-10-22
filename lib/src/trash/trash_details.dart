import 'package:insulink/src/sport/sport_format.dart';

import 'trash_entry.dart';

/// The facts of a trashed entry worth showing before restoring it, as pairs
/// of a `trash.detail.*` label key and the formatted value. Missing values are
/// left out.
class TrashDetails {
  const TrashDetails(this.entry);

  final TrashEntry entry;

  Map<String, dynamic> get _data => entry.data;

  List<(String, String)> get rows => [
    for (final (key, value) in _facts)
      if (value != null) ('trash.detail.$key', value),
  ];

  List<(String, String?)> get _facts => switch (entry.kind) {
    TrashKind.meal => [
      ('carbs', _amount('carbs', 0, 'g')),
      ('glucose', _amount('glucose', 0, 'mg/dL')),
      ('bolus', _amount('bolus', 1, 'U')),
      ('foods', _names('entries')),
    ],
    TrashKind.drink => [('volume', _amount('ml', 0, 'ml'))],
    TrashKind.weight => [('weight', _amount('kg', 1, 'kg'))],
    TrashKind.hba1c => [('hba1c', _amount('pct', 1, '%'))],
    TrashKind.cardio => [
      ('distance', '${sportDecimal((_data['dist'] as num) / 1000, 2)} km'),
      ('duration', _minutes()),
    ],
    TrashKind.workout => [('sets', _count('sets'))],
    TrashKind.routine => [('name', _text('name')), ('items', _count('items'))],
    TrashKind.exercise => [('name', _text('name'))],
    TrashKind.product => [
      ('name', _text('name')),
      ('brand', _text('brand')),
      ('carbs', _amount('carbs', 1, 'g / 100 g')),
      ('protein', _amount('protein', 1, 'g / 100 g')),
      ('fat', _amount('fat', 1, 'g / 100 g')),
      ('kcal', _amount('kcal', 0, 'kcal / 100 g')),
    ],
  };

  String? _amount(String key, int decimals, String unit) {
    final value = _data[key] as num?;
    if (value == null) {
      return null;
    }
    return '${sportDecimal(value.toDouble(), decimals)} $unit';
  }

  String? _text(String key) {
    final value = _data[key] as String?;
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String? _count(String key) => (_data[key] as List?)?.length.toString();

  String? _names(String key) {
    final names = [
      for (final item in (_data[key] as List? ?? const []))
        if ((item as Map)['name'] case final String name) name,
    ];
    if (names.isEmpty) {
      return null;
    }
    return names.join(', ');
  }

  String _minutes() {
    final span = (_data['end'] as int) - (_data['start'] as int);
    return '${Duration(milliseconds: span).inMinutes} min';
  }
}
