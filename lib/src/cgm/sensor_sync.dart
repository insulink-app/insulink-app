import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/inventory/inventory_item.dart';
import 'package:insulink/src/inventory/inventory_store.dart';
import 'package:insulink/src/inventory/inventory_sync.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Mirrors the paired sensor to the user's backend account so a fresh install
/// can offer to restore it (see [fetchCurrent]).
///
/// [sync] runs best-effort from the foreground-service isolate (no UI context,
/// stored token) right after a reading — it registers the sensor the first time
/// the identity is complete, then updates the backend only when that identity
/// changes (e.g. a re-pair rotates the session key). [fetchCurrent] runs in the
/// UI isolate, where [Request] can refresh an expired token.
class SensorSync {
  const SensorSync();

  /// Register or update the current sensor. Idempotent and cheap: it only POSTs
  /// on the first complete identity and whenever that identity changes.
  Future<void> sync(CgmStore store) async {
    final key = store.resolvedKey;
    if (key == null || key.isEmpty) {
      return;
    }
    final data = _data(store, key);
    if (data == null) {
      return;
    }
    final sensorId = store.backendSensorId(key);
    if (sensorId == null) {
      await _register(store, key, data);
    } else if (store.backendSyncedData(key) != data) {
      await _update(store, sensorId, key, data);
    }
  }

  /// The identity + sensor-info blob the backend stores opaquely and we decode on
  /// restore, tagged with `sensor_type` so the restore side knows which reconnect
  /// identity it holds. Null until the sensor is fully paired.
  // ponytail: the dedup keys on the whole blob, so a slowly-drifting field
  // (battery voltage) can trigger an update each reconnect — fine, it's one
  // small POST; split static vs volatile fields only if it proves chatty.
  String? _data(CgmStore store, String key) {
    return store.sensorType == SensorType.abbottLibre3
        ? _libreData(store, key)
        : _g7Data(store, key);
  }

  /// G7 identity: pairing code + BLE id + J-PAKE session key, plus the full
  /// [G7DeviceInfo] the sensor page shows.
  String? _g7Data(CgmStore store, String key) {
    final pairingCode = store.pairingCode;
    final deviceId = store.deviceId(key);
    final sessionKey = store.sessionKeyHex(key);
    if (pairingCode == null ||
        pairingCode.isEmpty ||
        deviceId == null ||
        sessionKey == null) {
      return null;
    }
    final start = store.loadSensorStart(key);
    final info = store.loadInfo(key);
    final latest = store.loadLatest(key);
    return jsonEncode({
      'sensor_type': store.sensorType.wireKey,
      'resolved_key': key,
      'pairing_code': pairingCode,
      'device_id': deviceId,
      'session_key': sessionKey,
      if (start != null) 'sensor_start': start.millisecondsSinceEpoch,
      if (info != null) 'info': info.toJson(),
      if (latest != null) 'state': latest['state'],
    });
  }

  /// Libre 3 identity: only the NFC-derived MAC + session info, so a fresh
  /// install recognises the sensor. Deliberately NO BLE PIN and NO cached kAuth:
  /// **the sensor issues a NEW BLE PIN on every NFC scan and honours only the
  /// latest one** (measured — a restored PIN made the sensor terminate the link
  /// on our challenge response, see docs/LIBRE3.md). A stored PIN is therefore
  /// worthless the moment anyone re-scans, and the kAuth derived from it with it;
  /// restoring a Libre 3 always needs a fresh NFC scan. Don't put either secret
  /// on the server for nothing.
  String? _libreData(CgmStore store, String key) {
    final mac = store.libreMac(key);
    if (mac == null || mac.isEmpty) {
      return null;
    }
    final start = store.loadSensorStart(key);
    final latest = store.loadLatest(key);
    return jsonEncode({
      'sensor_type': store.sensorType.wireKey,
      'resolved_key': key,
      'libre_mac': mac,
      if (start != null) 'sensor_start': start.millisecondsSinceEpoch,
      if (latest != null) 'state': latest['state'],
    });
  }

  /// Epoch-ms the sensor session ends — start plus its reported lifetime, else
  /// the active sensor's nominal lifetime (G7 ~10 d, Libre 3 14 d).
  int _expiresAt(CgmStore store, String key) {
    final start =
        store.loadSensorStart(key)?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    final lifetimeSec =
        store.loadInfo(key)?.sessionLengthSec ??
        store.sensorType.sessionLengthSec;
    return start + lifetimeSec * 1000;
  }

  Future<void> _register(CgmStore store, String key, String data) async {
    final response = await Request.post(
      url: '/sensor/register/',
      body: {
        'type': store.sensorType.backendType,
        'data': data,
        'expires_at': _expiresAt(store, key),
      },
    ).send(null);
    if (!_isSuccess(response)) {
      return;
    }
    final id = response.jsonObject?['sensor_id'];
    if (id != null) {
      await store.saveBackendSensorId(key, '$id');
      await store.saveBackendSyncedData(key, data);
      await _consumeFromInventory(store);
    }
  }

  /// A successful register is the one moment a sensor becomes newly known (it
  /// was neither local nor on the backend — a restore sets the id directly and
  /// never lands here), so this is where a paired Libre/Dexcom pulls one unit
  /// from the matching inventory item. The backend id now stored dedups it: the
  /// next syncs take the update path, so a sensor is only ever counted once.
  Future<void> _consumeFromInventory(CgmStore store) async {
    final brand = store.sensorType == SensorType.abbottLibre3
        ? SensorBrand.libre
        : SensorBrand.dexcom;
    if (await const InventoryStore().consumeSensor(brand)) {
      InventorySync().push();
    }
  }

  Future<void> _update(
    CgmStore store,
    String sensorId,
    String key,
    String data,
  ) async {
    final response = await Request.post(
      url: '/sensor/update/',
      body: {'sensor_id': sensorId, 'data': data},
    ).send(null);
    if (_isSuccess(response)) {
      await store.saveBackendSyncedData(key, data);
    }
  }

  /// Tells the account a stored sensor is gone, so it stops being offered.
  ///
  /// The record is what lets a reinstalled app pick up a sensor still on the
  /// body, so once that sensor is off it has nothing left to offer and would be
  /// suggested at every launch. Dismissing the offer used to write a flag on the
  /// DEVICE, which is no use in the one situation the offer exists for: a fresh
  /// install has no local flags.
  ///
  /// The record is KEPT and only stamped. It is the user's sensor history and
  /// belongs in the log whatever happened to the hardware; what stops is the
  /// offering, because `/sensor/current/` skips a stamped one.
  Future<bool> discard(String sensorId, BuildContext? context) async {
    final response = await Request.post(
      url: '/sensor/discard/',
      body: {'sensor_id': sensorId},
    ).send(context);
    if (!_isSuccess(response)) {
      debugPrint('sensor sync: discard REJECTED');
      return false;
    }
    return true;
  }

  /// The account's current sensor as a restorable identity, or null if there is
  /// none / the response was malformed. Call from the UI isolate.
  Future<SensorRestore?> fetchCurrent(BuildContext context) async {
    final response = await Request.get(url: '/sensor/current/').send(context);
    if (!_isSuccess(response)) {
      return null;
    }
    final body = response.jsonObject;
    if (body == null) {
      return null;
    }
    final id = body['id'];
    final data = body['data'];
    if (id == null || data is! String) {
      return null;
    }
    try {
      final blob = jsonDecode(data) as Map<String, dynamic>;
      return SensorRestore(
        sensorId: '$id',
        sensorType: SensorType.fromWireKey(blob['sensor_type'] as String?),
        resolvedKey: blob['resolved_key'] as String,
        pairingCode: blob['pairing_code'] as String?,
        deviceId: blob['device_id'] as String?,
        sessionKeyHex: blob['session_key'] as String?,
        libreMac: blob['libre_mac'] as String?,
        infoJson: blob['info'] as Map<String, dynamic>?,
        sensorStartMs: (blob['sensor_start'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  bool _isSuccess(Response? response) {
    if (response == null) {
      return false;
    }
    try {
      return response.isApiSuccess;
    } catch (_) {
      return false;
    }
  }
}

/// A backend sensor decoded into what the local store needs to adopt it.
/// [sensorType] selects which identity fields are populated: the G7
/// ([pairingCode]/[deviceId]/[sessionKeyHex]) reconnects straight from these; the
/// Libre 3 carries only [libreMac] and still needs an NFC scan for a fresh PIN
/// (see [SensorSync._libreData]).
class SensorRestore {
  const SensorRestore({
    required this.sensorId,
    required this.sensorType,
    required this.resolvedKey,
    this.pairingCode,
    this.deviceId,
    this.sessionKeyHex,
    this.libreMac,
    this.infoJson,
    this.sensorStartMs,
  });

  final String sensorId;
  final SensorType sensorType;
  final String resolvedKey;

  // G7 identity.
  final String? pairingCode;
  final String? deviceId;
  final String? sessionKeyHex;

  // Libre 3 identity (the PIN is NOT restorable — it needs an NFC re-scan).
  final String? libreMac;

  /// The sensor page info ([G7DeviceInfo] JSON) + session start, so the page
  /// populates immediately on restore instead of waiting for a reconnect.
  final Map<String, dynamic>? infoJson;
  final int? sensorStartMs;
}
