import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_info.dart';

/// Persists the sensor serial, pairing code, and the per-sensor EC-JPAKE
/// session key so the reader can reconnect without re-pairing.
class G7Store {
  static const _kSerial = 'g7.serial';
  static const _kCode = 'g7.pairing_code';
  static String _kKey(String serial) => 'g7.session_key.$serial';

  final SharedPreferences _p;
  G7Store(this._p);

  static Future<G7Store> open() async =>
      G7Store(await SharedPreferences.getInstance());

  /// Re-read values written by another isolate. Each isolate keeps its own
  /// in-memory SharedPreferences cache, so the UI must reload to observe writes
  /// made by the background foreground-service isolate (and vice-versa).
  Future<void> reload() => _p.reload();

  String? get serial => _p.getString(_kSerial);
  String? get pairingCode => _p.getString(_kCode);

  Future<void> saveIdentity({
    required String serial,
    required String pairingCode,
  }) async {
    await _p.setString(_kSerial, serial);
    await _p.setString(_kCode, pairingCode);
  }

  /// The stored session key for [serial], or null if never paired.
  Uint8List? sessionKey(String serial) {
    final hex = _p.getString(_kKey(serial));
    if (hex == null || hex.length < 32) return null;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  Future<void> saveSessionKey(String serial, Uint8List key) async {
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _p.setString(_kKey(serial), hex);
  }

  Future<void> clearSessionKey(String serial) => _p.remove(_kKey(serial));

  static String _kReadings(String serial) => 'g7.readings.$serial';

  /// Cache recent glucose history (keyed by seconds-since-session-start) so the
  /// chart can show something immediately on the next launch. Keeps the most
  /// recent ~300 points (≈24 h at 5-min cadence).
  Future<void> saveReadings(String serial, Map<int, int> byTime) async {
    final keys = byTime.keys.toList()..sort();
    final recent = keys.length > 300 ? keys.sublist(keys.length - 300) : keys;
    final s = recent.map((k) => '$k:${byTime[k]}').join(',');
    await _p.setString(_kReadings(serial), s);
  }

  Map<int, int> loadReadings(String serial) {
    final out = <int, int>{};
    final s = _p.getString(_kReadings(serial));
    if (s == null || s.isEmpty) return out;
    for (final part in s.split(',')) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      final k = int.tryParse(part.substring(0, i));
      final v = int.tryParse(part.substring(i + 1));
      if (k != null && v != null) out[k] = v;
    }
    return out;
  }

  static String _kLatest(String serial) => 'g7.latest.$serial';

  /// Cache the most recent live EGV (value + trend + state + session clock) so
  /// the big headline reading is restored immediately on the next launch — not
  /// just the last history point.
  Future<void> saveLatest(
    String serial, {
    required int? mgdl,
    required int trendTenths,
    required int state,
    required int secsSinceStart,
  }) async {
    await _p.setString(
      _kLatest(serial),
      jsonEncode({
        'mgdl': mgdl,
        'trend': trendTenths,
        'state': state,
        'secs': secsSinceStart,
      }),
    );
  }

  Map<String, dynamic>? loadLatest(String serial) {
    final s = _p.getString(_kLatest(serial));
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  static String _kInfo(String serial) => 'g7.info.$serial';
  static String _kStart(String serial) => 'g7.start.$serial';

  /// Cache device metadata + sensor session start so the info panel renders
  /// immediately on the next launch, before the version messages return.
  Future<void> saveInfo(
    String serial,
    G7DeviceInfo info,
    DateTime? start,
  ) async {
    await _p.setString(_kInfo(serial), jsonEncode(info.toJson()));
    if (start != null) {
      await _p.setInt(_kStart(serial), start.millisecondsSinceEpoch);
    }
  }

  G7DeviceInfo? loadInfo(String serial) {
    final s = _p.getString(_kInfo(serial));
    if (s == null) return null;
    return G7DeviceInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  DateTime? loadSensorStart(String serial) {
    final ms = _p.getInt(_kStart(serial));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
