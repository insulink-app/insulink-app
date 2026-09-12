import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One target band for a sleep metric, in minutes. The bar renders the [min]–
/// [max] window as the dashed target box; a value inside it counts as on-target.
class SleepTargetRange {
  final int min;
  final int max;

  const SleepTargetRange(this.min, this.max);

  bool contains(int value) => value >= min && value <= max;

  Map<String, dynamic> toJson() => {'min': min, 'max': max};

  factory SleepTargetRange.fromJson(Map<String, dynamic> json) =>
      SleepTargetRange(json['min'] as int, json['max'] as int);
}

/// The user's per-metric sleep target bands, persisted as one JSON blob in
/// secure storage. Same tiny load()/save() shape as the profile settings; only
/// the sleep detail page reads it, so it stays a plain data class (no notifier).
class SleepTargets {
  final SleepTargetRange timeToSolid;
  final SleepTargetRange deep;
  final SleepTargetRange interruption;

  const SleepTargets({
    required this.timeToSolid,
    required this.deep,
    required this.interruption,
  });

  SleepTargets copyWith({
    SleepTargetRange? timeToSolid,
    SleepTargetRange? deep,
    SleepTargetRange? interruption,
  }) => SleepTargets(
    timeToSolid: timeToSolid ?? this.timeToSolid,
    deep: deep ?? this.deep,
    interruption: interruption ?? this.interruption,
  );

  /// Defaults: fall asleep within ~30 min, ~1.5–2.5 h deep sleep, and few
  /// awakenings.
  static const defaults = SleepTargets(
    timeToSolid: SleepTargetRange(0, 30),
    deep: SleepTargetRange(75, 150),
    interruption: SleepTargetRange(0, 30),
  );

  /// Secure-storage key. Public so [ProfileSettings] can carry the same blob in
  /// its account settings sync (the value round-trips verbatim as one JSON
  /// string), keeping the sleep targets in sync across devices / re-login.
  static const key = 'sleep_targets';
  static const _storage = FlutterSecureStorage();

  Map<String, dynamic> toJson() => {
    'time_to_solid': timeToSolid.toJson(),
    'deep': deep.toJson(),
    'interruption': interruption.toJson(),
  };

  factory SleepTargets.fromJson(Map<String, dynamic> json) => SleepTargets(
    timeToSolid: SleepTargetRange.fromJson(
      (json['time_to_solid'] as Map).cast<String, dynamic>(),
    ),
    deep: SleepTargetRange.fromJson(
      (json['deep'] as Map).cast<String, dynamic>(),
    ),
    interruption: SleepTargetRange.fromJson(
      (json['interruption'] as Map).cast<String, dynamic>(),
    ),
  );

  static Future<SleepTargets> load() async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return defaults;
    }
    return SleepTargets.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// The stored blob verbatim (defaults' JSON when unset) — for [ProfileSettings]
  /// to include in the account settings sync.
  static Future<String> loadRaw() async {
    final raw = await _storage.read(key: key);
    return (raw == null || raw.isEmpty) ? jsonEncode(defaults.toJson()) : raw;
  }

  Future<void> save() => _storage.write(key: key, value: jsonEncode(toJson()));
}
