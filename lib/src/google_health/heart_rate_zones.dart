import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-configurable heart-rate zones for the pulse chart: green below
/// [elevated] bpm, orange up to [high] bpm, red above. Self-persists to secure
/// storage (like the Profile*State classes). Kept in the heart-rate feature
/// folder since only the pulse page uses it.
class HeartRateZones {
  final int elevated;
  final int high;

  const HeartRateZones({this.elevated = 100, this.high = 140});

  static const _storage = FlutterSecureStorage();
  static const _kElevated = 'hr_zone_elevated';
  static const _kHigh = 'hr_zone_high';

  /// Bounds so the two thresholds stay ordered and physiologically sane.
  static const minBpm = 50;
  static const maxBpm = 240;
  static const _gap = 5;

  static const green = Color(0xFF43A047);
  static const orange = Color(0xFFFB8C00);
  static const red = Color(0xFFE53935);

  /// Zone colour for a bpm value (green / orange / red).
  Color colorFor(num bpm) {
    if (bpm < elevated) {
      return green;
    }
    return bpm < high ? orange : red;
  }

  /// Zone index (0 green, 1 orange, 2 red) — used by the chart's band splitter.
  int zoneOf(num bpm) => bpm < elevated ? 0 : (bpm < high ? 1 : 2);

  List<Color> get colors => const [green, orange, red];

  /// Copy with clamped, still-ordered thresholds (elevated at least [_gap] below
  /// high).
  HeartRateZones copyWith({int? elevated, int? high}) {
    final nextHigh = (high ?? this.high).clamp(minBpm + _gap, maxBpm);
    final nextElevated =
        (elevated ?? this.elevated).clamp(minBpm, nextHigh - _gap);
    return HeartRateZones(elevated: nextElevated, high: nextHigh);
  }

  Future<void> save() async {
    await _storage.write(key: _kElevated, value: '$elevated');
    await _storage.write(key: _kHigh, value: '$high');
  }

  static Future<HeartRateZones> load() async {
    final elevated = int.tryParse(await _storage.read(key: _kElevated) ?? '');
    final high = int.tryParse(await _storage.read(key: _kHigh) ?? '');
    return const HeartRateZones()
        .copyWith(elevated: elevated, high: high);
  }
}
