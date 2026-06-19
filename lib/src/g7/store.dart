import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_info.dart';

/// Persists the sensor serial, pairing code, and the per-sensor EC-JPAKE
/// session key so the reader can reconnect without re-pairing.
///
/// Backed by [FlutterSecureStorage] (platform keystore / EncryptedSharedPrefs).
/// Reads are served synchronously from an in-memory [_cache] loaded on [open]
/// and refreshed by [reload]; writes go to secure storage and update the cache.
/// This keeps the synchronous getter API the read pipeline relies on while the
/// data lives encrypted at rest.
class G7Store {
  static const _kSerial = 'g7.serial';
  static const _kCode = 'g7.pairing_code';

  static String _kKey(String serial) => 'g7.session_key.$serial';

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache;

  G7Store(this._storage, this._cache);

  static Future<G7Store> open() async {
    const storage = FlutterSecureStorage();
    final cache = await storage.readAll();
    return G7Store(storage, cache);
  }

  /// Re-read values written by another isolate. The in-memory cache is local to
  /// this isolate, so the UI must reload to observe writes made by the
  /// background foreground-service isolate (and vice-versa).
  Future<void> reload() async {
    final all = await _storage.readAll();
    _cache
      ..clear()
      ..addAll(all);
  }

  Future<void> _set(String key, String value) async {
    await _storage.write(key: key, value: value);
    _cache[key] = value;
  }

  Future<void> _remove(String key) async {
    await _storage.delete(key: key);
    _cache.remove(key);
  }

  String? get serial => _cache[_kSerial];

  String? get pairingCode => _cache[_kCode];

  static const _kResolved = 'g7.resolved_key';

  /// The effective key all cached data is stored under: the user-entered serial,
  /// or the sensor's stable BLE id when no serial was entered. Decided by the
  /// read pipeline once a device is found; the UI reads cache under this key so
  /// caching works even when the serial field is left blank.
  String? get resolvedKey => _cache[_kResolved];

  Future<void> saveResolvedKey(String key) => _set(_kResolved, key);

  Future<void> saveIdentity({
    required String serial,
    required String pairingCode,
  }) async {
    await _set(_kSerial, serial);
    await _set(_kCode, pairingCode);
  }

  /// The stored session key for [serial], or null if never paired.
  Uint8List? sessionKey(String serial) {
    final hex = _cache[_kKey(serial)];
    if (hex == null || hex.length < 32) return null;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  Future<void> saveSessionKey(String serial, Uint8List key) async {
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _set(_kKey(serial), hex);
  }

  Future<void> clearSessionKey(String serial) => _remove(_kKey(serial));

  // The BLE remoteId of the physical sensor paired for this serial. Lets the
  // background service reconnect by id with autoConnect (no scan) — Android
  // throttles BLE scanning while the screen is off, but an OS-level autoConnect
  // fires as soon as the sensor advertises. Also pins to the right sensor when
  // several G7s are in range.
  static String _kDeviceId(String serial) => 'g7.device_id.$serial';

  String? deviceId(String serial) => _cache[_kDeviceId(serial)];

  Future<void> saveDeviceId(String serial, String id) =>
      _set(_kDeviceId(serial), id);

  static String _kReadings(String serial) => 'g7.readings.$serial';

  /// Cache recent glucose history (keyed by seconds-since-session-start) so the
  /// chart can show something immediately on the next launch. Keeps the most
  /// recent ~300 points (≈24 h at 5-min cadence).
  Future<void> saveReadings(String serial, Map<int, int> byTime) async {
    final keys = byTime.keys.toList()..sort();
    final recent = keys.length > 300 ? keys.sublist(keys.length - 300) : keys;
    final s = recent.map((k) => '$k:${byTime[k]}').join(',');
    await _set(_kReadings(serial), s);
  }

  Map<int, int> loadReadings(String serial) {
    final out = <int, int>{};
    final s = _cache[_kReadings(serial)];
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
    await _set(
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
    final s = _cache[_kLatest(serial)];
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
    await _set(_kInfo(serial), jsonEncode(info.toJson()));
    if (start != null) {
      await _set(_kStart(serial), start.millisecondsSinceEpoch.toString());
    }
  }

  G7DeviceInfo? loadInfo(String serial) {
    final s = _cache[_kInfo(serial)];
    if (s == null) return null;
    return G7DeviceInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  DateTime? loadSensorStart(String serial) {
    final ms = int.tryParse(_cache[_kStart(serial)] ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
