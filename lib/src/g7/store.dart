import 'dart:collection';
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
    if (hex == null || hex.length < 32) {
      return null;
    }
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

  /// Forget a sensor entirely: drop its session key + all cached data, plus the
  /// resolved key and identity, so the app no longer auto-reconnects to it.
  Future<void> clearSensor(String key) async {
    for (final k in [
      _kKey(key),
      _kDeviceId(key),
      _kReadings(key),
      _kLatest(key),
      _kInfo(key),
      _kStart(key),
      _kExpiryNotified(key),
    ]) {
      await _remove(k);
    }
    await _remove(_kResolved);
    await _remove(_kSerial);
    await _remove(_kCode);
  }

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
    if (s == null || s.isEmpty) {
      return out;
    }
    for (final part in s.split(',')) {
      final i = part.indexOf(':');
      if (i <= 0) {
        continue;
      }
      final k = int.tryParse(part.substring(0, i));
      final v = int.tryParse(part.substring(i + 1));
      if (k != null && v != null) {
        out[k] = v;
      }
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
    if (s == null) {
      return null;
    }
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
    if (s == null) {
      return null;
    }
    return G7DeviceInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  DateTime? loadSensorStart(String serial) {
    final ms = int.tryParse(_cache[_kStart(serial)] ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static String _kExpiryNotified(String serial) => 'g7.expiry_notified.$serial';

  /// Whether the "sensor expires soon" notification already fired for this
  /// sensor — so it only fires once per sensor (cleared by [clearSensor]).
  bool expiryNotified(String serial) =>
      _cache[_kExpiryNotified(serial)] == 'true';

  Future<void> setExpiryNotified(String serial) =>
      _set(_kExpiryNotified(serial), 'true');

  // ---- Long-term glucose archive -------------------------------------------
  // An append-only, absolute-time glucose record that SURVIVES sensor swap,
  // sensor stop, connection loss and even "forget sensor". The per-sensor
  // [saveReadings] cache above is session-relative (keyed by seconds-since-
  // session-start), capped at ~300 points and wiped when a new session resets
  // the clock — fine for restoring the current chart, useless as history.
  //
  // This archive instead keys readings by absolute epoch-minute, bucketed into
  // day-sized chunks (`g7.hist.<dayIndex>`) so each new reading rewrites only
  // the current day's chunk, not the whole record. It is deliberately NOT keyed
  // by serial and NOT removed by [clearSensor], so the chart/statistics retain a
  // continuous record across every sensor the user has worn.

  static const _kHistPrefix = 'g7.hist.';
  static const _minsPerDay = 1440;

  /// Epoch minutes (timezone-independent — `millisecondsSinceEpoch` is UTC).
  static int _epochMin(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;

  static String _kHist(int dayIndex) => '$_kHistPrefix$dayIndex';

  Map<int, int> _loadHistDay(int dayIndex) {
    final out = <int, int>{};
    final s = _cache[_kHist(dayIndex)];
    if (s == null || s.isEmpty) {
      return out;
    }
    for (final part in s.split(',')) {
      final i = part.indexOf(':');
      if (i <= 0) {
        continue;
      }
      final k = int.tryParse(part.substring(0, i));
      final v = int.tryParse(part.substring(i + 1));
      if (k != null && v != null) {
        out[k] = v;
      }
    }
    return out;
  }

  String _encodeHistDay(Map<int, int> day) {
    final keys = day.keys.toList()..sort();
    return keys.map((k) => '$k:${day[k]}').join(',');
  }

  // Serializes archive read-modify-writes. Callers fire archive appends WITHOUT
  // awaiting (from BLE stream listeners), so a live-EGV append racing a backfill
  // batch on the same day-chunk would otherwise clobber it — the big 24h backfill
  // gets wiped by a 1-point EGV write, leaving the archive sparse. Chaining every
  // append onto this gate makes each load→merge→store atomic w.r.t. the others.
  Future<void> _archiveGate = Future.value();

  /// Append one reading at its true wall-clock time [t] (deduped to the minute).
  Future<void> archiveAdd(DateTime t, int mgdl) => archiveAddAll({t: mgdl});

  /// Append a batch (e.g. a whole backfill block) in one pass, rewriting each
  /// affected day-chunk only once. Readings on the same minute dedupe (a live
  /// EGV and the backfill copy of it map to the same absolute minute).
  Future<void> archiveAddAll(Map<DateTime, int> readings) {
    if (readings.isEmpty) {
      return Future.value();
    }
    return _archiveGate = _archiveGate.then((_) => _archiveAddAll(readings));
  }

  Future<void> _archiveAddAll(Map<DateTime, int> readings) async {
    final byDay = <int, Map<int, int>>{};
    readings.forEach((t, mgdl) {
      final min = _epochMin(t);
      (byDay[min ~/ _minsPerDay] ??= {})[min] = mgdl;
    });
    for (final entry in byDay.entries) {
      final merged = _loadHistDay(entry.key)..addAll(entry.value);
      await _set(_kHist(entry.key), _encodeHistDay(merged));
    }
  }

  /// All archived readings in [from]..[to] inclusive, keyed by epoch-minute.
  /// Recover a point's wall-clock time with
  /// `DateTime.fromMillisecondsSinceEpoch(min * 60000)`.
  SplayTreeMap<int, int> archiveRange(DateTime from, DateTime to) {
    final out = SplayTreeMap<int, int>();
    final fromMin = _epochMin(from);
    final toMin = _epochMin(to);
    for (var d = fromMin ~/ _minsPerDay; d <= toMin ~/ _minsPerDay; d++) {
      _loadHistDay(d).forEach((k, v) {
        if (k >= fromMin && k <= toMin) {
          out[k] = v;
        }
      });
    }
    return out;
  }

  /// Drop archive day-chunks older than [keep] so storage stays bounded.
  /// Best-effort; only writes when there is actually something stale to remove.
  Future<void> archivePrune(Duration keep) async {
    final cutoffDay =
        (_epochMin(DateTime.now()) - keep.inMinutes) ~/ _minsPerDay;
    final stale = _cache.keys.where((k) => k.startsWith(_kHistPrefix)).where((
      k,
    ) {
      final d = int.tryParse(k.substring(_kHistPrefix.length));
      return d != null && d < cutoffDay;
    }).toList();
    for (final k in stale) {
      await _remove(k);
    }
  }
}
