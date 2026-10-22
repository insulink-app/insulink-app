import 'package:flutter/widgets.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// What a [TrashEntry] holds, with the icon its row shows. Its title is the
/// locale key `trash.kind.<name>`.
enum TrashKind {
  meal(PhosphorIconsBold.forkKnife),
  drink(PhosphorIconsBold.drop),
  weight(PhosphorIconsBold.scales),
  hba1c(PhosphorIconsBold.testTube),
  cardio(PhosphorIconsBold.personSimpleRun),
  workout(PhosphorIconsBold.barbell),
  routine(PhosphorIconsBold.listChecks),
  exercise(PhosphorIconsBold.barbell),
  product(PhosphorIconsBold.barcode);

  const TrashKind(this.icon);

  final IconData icon;

  String get titleKey => 'trash.kind.$name';
}

/// One deleted thing, kept as the same JSON its own store writes, so restoring
/// it is a plain `fromJson` into the state it came from.
class TrashEntry {
  const TrashEntry({
    required this.kind,
    required this.deletedAtMs,
    required this.data,
  });

  final TrashKind kind;
  final int deletedAtMs;
  final Map<String, dynamic> data;

  /// When the deleted thing itself happened (a meal, a training's start), or
  /// the deletion for things without a time of their own (a routine).
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(
    (data[_timeKey] as int?) ?? deletedAtMs,
  );

  String? get _timeKey => switch (kind) {
    TrashKind.meal => 'time',
    TrashKind.drink => 'at',
    TrashKind.weight || TrashKind.hba1c => 'ts',
    TrashKind.cardio => 'start',
    TrashKind.workout => 'started',
    _ => null,
  };

  /// A short line naming which one it was: an amount or a name.
  String? get summary => switch (kind) {
    TrashKind.meal => '${_number('carbs', 0)} g',
    TrashKind.drink => '${data['ml']} ml',
    TrashKind.weight => '${_number('kg', 1)} kg',
    TrashKind.hba1c => '${_number('pct', 1)} %',
    TrashKind.cardio => '${sportDecimal((data['dist'] as num) / 1000, 1)} km',
    TrashKind.workout => null,
    _ => data['name'] as String?,
  };

  String _number(String key, int decimals) =>
      sportDecimal((data[key] as num).toDouble(), decimals);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'deleted_at': deletedAtMs,
    'data': data,
  };

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
    kind: TrashKind.values.byName(json['kind'] as String),
    deletedAtMs: json['deleted_at'] as int,
    data: (json['data'] as Map).cast<String, dynamic>(),
  );
}
