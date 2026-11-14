import 'dart:convert';

import 'package:insulink/src/auth/data_key/data_key.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';

/// A backend sensor decoded into what the local store needs to adopt it.
/// [sensorType] selects which identity fields are populated: the G7
/// ([pairingCode]/[deviceId]/[sessionKeyHex]) reconnects straight from these; the
/// Libre 3 carries only [libreMac] and still needs an NFC scan for a fresh PIN
/// (see `SensorSync._libreData`).
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

  /// The account record [sensorId] decoded from its stored blob [data], or null
  /// when the blob is malformed. [dataKey] opens a sealed G7 session key; without
  /// it the identity comes back keyless and the sensor pairs afresh. Used for the
  /// `/sensor/current/` offer and for pairing again from the history alike.
  static SensorRestore? decode(String sensorId, String data, DataKey? dataKey) {
    try {
      final blob = jsonDecode(data) as Map<String, dynamic>;
      return SensorRestore(
        sensorId: sensorId,
        sensorType: SensorType.fromWireKey(blob['sensor_type'] as String?),
        resolvedKey: blob['resolved_key'] as String,
        pairingCode: blob['pairing_code'] as String?,
        deviceId: blob['device_id'] as String?,
        sessionKeyHex: _sessionKey(blob, dataKey),
        libreMac: blob['libre_mac'] as String?,
        infoJson: blob['info'] as Map<String, dynamic>?,
        sensorStartMs: (blob['sensor_start'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// The session key of a stored blob: the plain one of an older blob, or the
  /// opened sealed one; null when it is sealed with a key this device lacks,
  /// which leaves the sensor to pair afresh.
  static String? _sessionKey(Map<String, dynamic> blob, DataKey? key) {
    final sealed = blob['session_key_enc'] as String?;
    if (sealed == null) {
      return blob['session_key'] as String?;
    }
    final opened = key?.open(sealed);
    return opened == null ? null : utf8.decode(opened);
  }

  /// Whether adopting it can work: a Libre 3 always goes on to its NFC scan, a
  /// G7 needs its BLE id and a session key this device could open.
  bool get isAdoptable =>
      sensorType == SensorType.abbottLibre3 ||
      (deviceId != null && sessionKeyHex != null);

  final String sensorId;
  final SensorType sensorType;
  final String resolvedKey;

  // G7 identity.
  final String? pairingCode;
  final String? deviceId;
  final String? sessionKeyHex;

  // Libre 3 identity (the PIN is NOT restorable, it needs an NFC re-scan).
  final String? libreMac;

  /// The sensor page info ([G7DeviceInfo] JSON) + session start, so the page
  /// populates immediately on restore instead of waiting for a reconnect.
  final Map<String, dynamic>? infoJson;
  final int? sensorStartMs;
}
