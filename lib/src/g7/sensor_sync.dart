import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/g7/store.dart';
import 'package:insulink/src/request/request.dart';

/// Mirrors the paired sensor to the user's backend account so a fresh install
/// can offer to restore it (see [fetchCurrent]).
///
/// [sync] runs best-effort from the foreground-service isolate (no UI context,
/// stored token) right after a reading — it registers the sensor the first time
/// the identity is complete, then updates the backend only when that identity
/// changes (e.g. a re-pair rotates the session key). [fetchCurrent] runs in the
/// UI isolate, where [Request] can refresh an expired token.
class SensorSync {
  // The only sensor kind this app reads; matches the backend SensorType enum.
  static const _type = 'DEXCOM_G7';

  // Fallback G7 lifetime (10 days + 12 h grace) when the sensor hasn't reported
  // its session length yet — same fallback the expiry warning uses.
  static const _fallbackLifetimeSec = 907200;

  /// Register or update the current sensor. Idempotent and cheap: it only POSTs
  /// on the first complete identity and whenever that identity changes.
  Future<void> sync(G7Store store) async {
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
  /// restore. Carries everything the sensor page shows (the full [G7DeviceInfo],
  /// session start and algorithm state) on top of the reconnect identity. Null
  /// until the sensor is fully paired (pairing code + BLE id + session key).
  // ponytail: the dedup keys on the whole blob, so a slowly-drifting field
  // (battery voltage) can trigger an update each reconnect — fine, it's one
  // small POST; split static vs volatile fields only if it proves chatty.
  String? _data(G7Store store, String key) {
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
      'resolved_key': key,
      'pairing_code': pairingCode,
      'device_id': deviceId,
      'session_key': sessionKey,
      if (start != null) 'sensor_start': start.millisecondsSinceEpoch,
      if (info != null) 'info': info.toJson(),
      if (latest != null) 'state': latest['state'],
    });
  }

  /// Epoch-ms the sensor session ends — start plus its reported lifetime.
  int _expiresAt(G7Store store, String key) {
    final start =
        store.loadSensorStart(key)?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    final lifetimeSec =
        store.loadInfo(key)?.sessionLengthSec ?? _fallbackLifetimeSec;
    return start + lifetimeSec * 1000;
  }

  Future<void> _register(G7Store store, String key, String data) async {
    final response = await Request.post(
      url: '/sensor/register/',
      body: {'type': _type, 'data': data, 'expires_at': _expiresAt(store, key)},
    ).send(null);
    if (!_isSuccess(response)) {
      return;
    }
    final id = jsonDecode(response!.body)['sensor_id'];
    if (id != null) {
      await store.saveBackendSensorId(key, '$id');
      await store.saveBackendSyncedData(key, data);
    }
  }

  Future<void> _update(
    G7Store store,
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

  /// The account's current sensor as a restorable identity, or null if there is
  /// none / the response was malformed. Call from the UI isolate.
  Future<SensorRestore?> fetchCurrent(BuildContext context) async {
    final response = await Request.get(url: '/sensor/current/').send(context);
    if (!_isSuccess(response)) {
      return null;
    }
    final body = jsonDecode(response!.body);
    final id = body['id'];
    final data = body['data'];
    if (id == null || data is! String) {
      return null;
    }
    try {
      final blob = jsonDecode(data) as Map<String, dynamic>;
      return SensorRestore(
        sensorId: '$id',
        resolvedKey: blob['resolved_key'] as String,
        pairingCode: blob['pairing_code'] as String,
        deviceId: blob['device_id'] as String,
        sessionKeyHex: blob['session_key'] as String,
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
      return jsonDecode(response.body)['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

/// A backend sensor decoded into everything the local store needs to reconnect
/// without re-pairing.
class SensorRestore {
  const SensorRestore({
    required this.sensorId,
    required this.resolvedKey,
    required this.pairingCode,
    required this.deviceId,
    required this.sessionKeyHex,
    this.infoJson,
    this.sensorStartMs,
  });

  final String sensorId;
  final String resolvedKey;
  final String pairingCode;
  final String deviceId;
  final String sessionKeyHex;

  /// The sensor page info ([G7DeviceInfo] JSON) + session start, so the page
  /// populates immediately on restore instead of waiting for a reconnect.
  final Map<String, dynamic>? infoJson;
  final int? sensorStartMs;
}
