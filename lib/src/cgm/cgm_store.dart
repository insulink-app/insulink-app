import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cgm_connection.dart';
import 'protocol/device_info.dart';

/// Persists the sensor serial, pairing code, and the per-sensor EC-JPAKE
/// session key so the reader can reconnect without re-pairing.
///
/// Backed by [FlutterSecureStorage] (platform keystore / EncryptedSharedPrefs).
/// Reads are served synchronously from an in-memory [_cache] loaded on [open]
/// and refreshed by [reload]; writes go to secure storage and update the cache.
/// This keeps the synchronous getter API the read pipeline relies on while the
/// data lives encrypted at rest.
class CgmStore {
  static const _kSerial = 'g7.serial';
  static const _kCode = 'g7.pairing_code';

  static String _kKey(String serial) => 'g7.session_key.$serial';

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache;

  CgmStore(this._storage, this._cache);

  static Future<CgmStore> open() async {
    const storage = FlutterSecureStorage();
    final cache = await storage.readAll();
    return CgmStore(storage, cache);
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

  static const _kSensorType = 'cgm.type';

  /// Which CGM the current pairing is for. Defaults to the Dexcom G7 (the
  /// original, only sensor), so installs that predate this key keep reading.
  SensorType get sensorType => SensorType.fromWireKey(_cache[_kSensorType]);

  Future<void> saveSensorType(SensorType type) =>
      _set(_kSensorType, type.wireKey);

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
      for (var offset = 0; offset < hex.length; offset += 2)
        int.parse(hex.substring(offset, offset + 2), radix: 16),
    ]);
  }

  Future<void> saveSessionKey(String serial, Uint8List key) async {
    final hex = key
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _set(_kKey(serial), hex);
  }

  /// The raw hex session key (the wire form persisted under [serial]) — used by
  /// the backend sync to ship/restore the key without re-deriving bytes.
  String? sessionKeyHex(String serial) => _cache[_kKey(serial)];

  Future<void> saveSessionKeyHex(String serial, String hex) =>
      _set(_kKey(serial), hex);

  Future<void> clearSessionKey(String serial) => _remove(_kKey(serial));

  // ---- FreeStyle Libre 3 (NFC-derived + cached auth key) -------------------
  // The BLE MAC + 4-byte PIN come from the NFC activation scan; the 16-byte
  // kAuth is derived at the end of the BLE handshake and cached so the next
  // reconnect can take the fast pre-authorised path. All keyed by resolved key.

  static String _kLibreMac(String key) => 'libre3.mac.$key';
  static String _kLibrePin(String key) => 'libre3.pin.$key';
  static String _kLibreAuth(String key) => 'libre3.auth.$key';

  String? libreMac(String key) => _cache[_kLibreMac(key)];

  Future<void> saveLibreMac(String key, String mac) =>
      _set(_kLibreMac(key), mac);

  Uint8List? librePin(String key) => _decodeHex(_cache[_kLibrePin(key)]);

  Future<void> saveLibrePin(String key, Uint8List pin) =>
      _set(_kLibrePin(key), _encodeHex(pin));

  Uint8List? libreAuthKey(String key) => _decodeHex(_cache[_kLibreAuth(key)]);

  Future<void> saveLibreAuthKey(String key, Uint8List authKey) =>
      _set(_kLibreAuth(key), _encodeHex(authKey));

  // Hex passthroughs for the backend sensor blob (SensorSync) — the values are
  // already stored as hex, so avoid a decode/re-encode round trip.
  String? librePinHex(String key) => _cache[_kLibrePin(key)];

  Future<void> saveLibrePinHex(String key, String hex) =>
      _set(_kLibrePin(key), hex);

  String? libreAuthKeyHex(String key) => _cache[_kLibreAuth(key)];

  Future<void> saveLibreAuthKeyHex(String key, String hex) =>
      _set(_kLibreAuth(key), hex);

  static String _encodeHex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List? _decodeHex(String? hex) {
    if (hex == null || hex.isEmpty || hex.length.isOdd) {
      return null;
    }
    return Uint8List.fromList([
      for (var offset = 0; offset < hex.length; offset += 2)
        int.parse(hex.substring(offset, offset + 2), radix: 16),
    ]);
  }

  // ---- Backend sensor sync -------------------------------------------------
  // Bookkeeping for mirroring the paired sensor to the account: the backend's
  // sensor UUID and the last identity blob we shipped, BOTH keyed by the
  // resolved sensor key so a NEW sensor registers a fresh row instead of
  // overwriting the previous one. Plus a one-shot "the user dismissed the
  // restore offer for this backend sensor" flag.

  static String _kBackendId(String key) => 'g7.backend_id.$key';
  static String _kBackendData(String key) => 'g7.backend_data.$key';
  static const _kRestoreDismissed = 'g7.restore_dismissed';

  String? backendSensorId(String key) => _cache[_kBackendId(key)];

  Future<void> saveBackendSensorId(String key, String id) =>
      _set(_kBackendId(key), id);

  String? backendSyncedData(String key) => _cache[_kBackendData(key)];

  Future<void> saveBackendSyncedData(String key, String data) =>
      _set(_kBackendData(key), data);

  String? get restoreDismissedId => _cache[_kRestoreDismissed];

  Future<void> setRestoreDismissed(String backendSensorId) =>
      _set(_kRestoreDismissed, backendSensorId);

  /// Forget a sensor entirely: drop its session key + all cached data, plus the
  /// resolved key and identity, so the app no longer auto-reconnects to it.
  Future<void> clearSensor(String key) async {
    for (final sensorKey in [
      _kKey(key),
      _kDeviceId(key),
      _kReadings(key),
      _kLatest(key),
      _kInfo(key),
      _kStart(key),
      _kExpiryNotified(key),
      _kHalftimeNotified(key),
      _kLibreMac(key),
      _kLibrePin(key),
      _kLibreAuth(key),
    ]) {
      await _remove(sensorKey);
    }
    await _remove(_kResolved);
    await _remove(_kSerial);
    await _remove(_kCode);
    await _remove(_kSensorType);
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

  /// Decodes the `"k:v,k:v"` int-map wire format shared by the per-session
  /// readings cache and the long-term archive day-chunks.
  Map<int, int> _decodeIntMap(String? raw) {
    final out = <int, int>{};
    if (raw == null || raw.isEmpty) {
      return out;
    }
    for (final part in raw.split(',')) {
      final colon = part.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      final key = int.tryParse(part.substring(0, colon));
      final value = int.tryParse(part.substring(colon + 1));
      if (key != null && value != null) {
        out[key] = value;
      }
    }
    return out;
  }

  /// Encodes an int-map to the `"k:v,k:v"` wire format, key-sorted.
  String _encodeIntMap(Map<int, int> map) {
    final keys = map.keys.toList()..sort();
    return keys.map((key) => '$key:${map[key]}').join(',');
  }

  static String _kReadings(String serial) => 'g7.readings.$serial';

  /// Cache recent glucose history (keyed by seconds-since-session-start) so the
  /// chart can show something immediately on the next launch. Keeps the most
  /// recent 24 h by time — cadence-independent, so the Libre 3's 1-min stream
  /// gets the same backlog window as the G7's 5-min one (a fixed point count
  /// would give the Libre only ~5 h).
  static const int _readingsWindowSec = 24 * 3600;

  Future<void> saveReadings(String serial, Map<int, int> byTime) async {
    final cutoff = byTime.keys.isEmpty
        ? 0
        : byTime.keys.reduce((a, b) => a > b ? a : b) - _readingsWindowSec;
    final capped = {
      for (final entry in byTime.entries)
        if (entry.key >= cutoff) entry.key: entry.value,
    };
    await _set(_kReadings(serial), _encodeIntMap(capped));
  }

  Map<int, int> loadReadings(String serial) =>
      _decodeIntMap(_cache[_kReadings(serial)]);

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
    final raw = _cache[_kLatest(serial)];
    if (raw == null) {
      return null;
    }
    return jsonDecode(raw) as Map<String, dynamic>;
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
    final raw = _cache[_kInfo(serial)];
    if (raw == null) {
      return null;
    }
    return G7DeviceInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  DateTime? loadSensorStart(String serial) {
    final ms = int.tryParse(_cache[_kStart(serial)] ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Persist just the session start. The G7 carries it via [saveInfo], but the
  /// Libre 3 has no [G7DeviceInfo] — and without a stored start the headline
  /// reads a cached value as stale (grey) and the stale-recovery restarts the
  /// service on every launch.
  Future<void> saveSensorStart(String serial, DateTime start) =>
      _set(_kStart(serial), start.millisecondsSinceEpoch.toString());

  static String _kExpiryNotified(String serial) => 'g7.expiry_notified.$serial';

  /// Whether the "sensor expires soon" notification already fired for this
  /// sensor — so it only fires once per sensor (cleared by [clearSensor]).
  bool expiryNotified(String serial) =>
      _cache[_kExpiryNotified(serial)] == 'true';

  Future<void> setExpiryNotified(String serial) =>
      _set(_kExpiryNotified(serial), 'true');

  static String _kHalftimeNotified(String serial) =>
      'g7.halftime_notified.$serial';

  /// Whether the "sensor halfway through its life" notification already fired for
  /// this sensor — so it only fires once per sensor (cleared by [clearSensor]).
  bool halftimeNotified(String serial) =>
      _cache[_kHalftimeNotified(serial)] == 'true';

  Future<void> setHalftimeNotified(String serial) =>
      _set(_kHalftimeNotified(serial), 'true');

  static const _kLastRestart = 'g7.last_service_restart';

  /// Wall-clock (epoch ms) of the last in-process `restartService()` the
  /// watchdog fired. Persisted in secure storage (process-wide, unlike the
  /// per-isolate cache) so the FRESH isolate that restart spawned can tell a
  /// restart was JUST attempted. If data is still absent after one, the native
  /// BLE stack — not the isolate — is wedged, and only a full PROCESS restart
  /// clears it (`restartService()` reuses the same process). See [CgmTaskHandler].
  DateTime? get lastServiceRestartAt {
    final ms = int.tryParse(_cache[_kLastRestart] ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markServiceRestart() =>
      _set(_kLastRestart, DateTime.now().millisecondsSinceEpoch.toString());

  // ---- Event log -----------------------------------------------------------
  // A small append-only log of notable events (glucose lows/highs, signal loss,
  // sensor swap/stop) for the analysis "events" page. Kept in one JSON array
  // (events are rare — zone crossings and sensor lifecycle), capped, and — like
  // the archive — NOT wiped by clearSensor, so it spans sensors.

  static const _kEvents = 'g7.events';
  static const _eventCap = 200;

  List<Map<String, dynamic>> _rawEvents() {
    final raw = _cache[_kEvents];
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  /// Append an event of [type] (a stable slug the UI maps to a label/icon),
  /// optionally with the glucose [value] in mg/dL that triggered it.
  // ponytail: single-key read-modify-write without a cross-isolate lock —
  // events are infrequent, so a lost append under a rare two-isolate race is
  // acceptable; switch to per-day chunks like the archive if volume grows.
  Future<void> addEvent(String type, {DateTime? at, int? value}) async {
    final list = _rawEvents()
      ..add({
        'ts': (at ?? DateTime.now()).millisecondsSinceEpoch,
        'type': type,
        'value': ?value,
      });
    if (list.length > _eventCap) {
      list.removeRange(0, list.length - _eventCap);
    }
    await _set(_kEvents, jsonEncode(list));
  }

  /// Logged events within [from]..[to] inclusive, newest first. [value] is the
  /// mg/dL reading for glucose events, null otherwise.
  List<({DateTime time, String type, int? value})> eventsBetween(
    DateTime from,
    DateTime to,
  ) {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final out = <({DateTime time, String type, int? value})>[];
    for (final event in _rawEvents()) {
      final ts = event['ts'] as int;
      if (ts >= fromMs && ts <= toMs) {
        out.add((
          time: DateTime.fromMillisecondsSinceEpoch(ts),
          type: event['type'] as String,
          value: event['value'] as int?,
        ));
      }
    }
    out.sort((first, second) => second.time.compareTo(first.time));
    return out;
  }

  /// Merge backend-pulled events into the log, skipping any with the same
  /// (timestamp, type) already stored. Used by the sign-in pull so a fresh
  /// install gets its history without duplicating events it already logged.
  Future<void> mergeEvents(
    List<({DateTime time, String type, int? value})> events,
  ) async {
    final list = _rawEvents();
    final seen = list.map((event) => '${event['ts']}@${event['type']}').toSet();
    for (final event in events) {
      final ts = event.time.millisecondsSinceEpoch;
      if (seen.add('$ts@${event.type}')) {
        list.add({'ts': ts, 'type': event.type, 'value': ?event.value});
      }
    }
    list.sort(
      (first, second) => (first['ts'] as int).compareTo(second['ts'] as int),
    );
    if (list.length > _eventCap) {
      list.removeRange(0, list.length - _eventCap);
    }
    await _set(_kEvents, jsonEncode(list));
  }

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
  // by serial and NOT removed by [clearSensor], so the chart/analysis retain a
  // continuous record across every sensor the user has worn.

  static const _kHistPrefix = 'g7.hist.';
  static const _minsPerDay = 1440;

  /// Epoch minutes (timezone-independent — `millisecondsSinceEpoch` is UTC).
  static int _epochMin(DateTime time) => time.millisecondsSinceEpoch ~/ 60000;

  static String _kHist(int dayIndex) => '$_kHistPrefix$dayIndex';

  Map<int, int> _loadHistDay(int dayIndex) =>
      _decodeIntMap(_cache[_kHist(dayIndex)]);

  // Serializes archive read-modify-writes. Callers fire archive appends WITHOUT
  // awaiting (from BLE stream listeners), so a live-EGV append racing a backfill
  // batch on the same day-chunk would otherwise clobber it — the big 24h backfill
  // gets wiped by a 1-point EGV write, leaving the archive sparse. Chaining every
  // append onto this gate makes each load→merge→store atomic w.r.t. the others.
  Future<void> _archiveGate = Future.value();

  /// Append one reading at its true wall-clock [time] (deduped to the minute).
  Future<void> archiveAdd(DateTime time, int mgdl) =>
      archiveAddAll({time: mgdl});

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
    readings.forEach((time, mgdl) {
      final minute = _epochMin(time);
      (byDay[minute ~/ _minsPerDay] ??= {})[minute] = mgdl;
    });
    for (final entry in byDay.entries) {
      final merged = _loadHistDay(entry.key)..addAll(entry.value);
      await _set(_kHist(entry.key), _encodeIntMap(merged));
    }
  }

  /// All archived readings in [from]..[to] inclusive, keyed by epoch-minute.
  /// Recover a point's wall-clock time with
  /// `DateTime.fromMillisecondsSinceEpoch(min * 60000)`.
  SplayTreeMap<int, int> archiveRange(DateTime from, DateTime to) {
    final out = SplayTreeMap<int, int>();
    final fromMin = _epochMin(from);
    final toMin = _epochMin(to);
    for (var day = fromMin ~/ _minsPerDay; day <= toMin ~/ _minsPerDay; day++) {
      _loadHistDay(day).forEach((minute, mgdl) {
        if (minute >= fromMin && minute <= toMin) {
          out[minute] = mgdl;
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
    final stale = _cache.keys
        .where((key) => key.startsWith(_kHistPrefix))
        .where((key) {
          final day = int.tryParse(key.substring(_kHistPrefix.length));
          return day != null && day < cutoffDay;
        })
        .toList();
    for (final key in stale) {
      await _remove(key);
    }
  }
}
