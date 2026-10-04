import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

import 'device_record.dart';

/// Which device log to read. Each kind knows its endpoint, the list key in the
/// reply, and the page title, so the page itself is written once.
enum DeviceHistoryKind {
  sensors('/sensor/history/', 'sensors', 'connections.history.sensors'),
  pumps('/pump/history/', 'pumps', 'connections.history.pumps');

  const DeviceHistoryKind(this.path, this.listKey, this.titleKey);

  final String path;
  final String listKey;
  final String titleKey;
}

/// Reads the device history off the account.
///
/// Nothing is stored a second time on the phone for this: `SensorSync` and
/// `PumpSync` already register every sensor and pod, and a discarded one is only
/// stamped rather than deleted, exactly so the row stays the user's device log.
class DeviceHistorySync {
  const DeviceHistorySync();

  /// Every device of [kind] the account has held, or null when the request
  /// failed, so the page can say so rather than show an empty log.
  Future<List<DeviceRecord>?> fetch(
    DeviceHistoryKind kind,
    BuildContext context,
  ) async {
    final response = await Request.get(url: kind.path).send(context);
    if (!response.isApiSuccess) {
      return null;
    }
    final rows = response.jsonObject?[kind.listKey];
    if (rows is! List) {
      return null;
    }
    return [
      for (final row in rows.whereType<Map<String, dynamic>>())
        ?_record(kind, row),
    ];
  }

  /// One row decoded, or null when it carries no usable timestamps — a record
  /// the history cannot place is left out rather than drawn at the epoch.
  DeviceRecord? _record(DeviceHistoryKind kind, Map<String, dynamic> row) {
    final registeredAt = _time(row['registered_at']);
    final expiresAt = _time(row['expires_at']);
    if (registeredAt == null || expiresAt == null) {
      return null;
    }
    final blob = _blob(row['data']);
    final isSensor = kind == DeviceHistoryKind.sensors;
    return DeviceRecord(
      deviceKey: _deviceKey(isSensor, blob, row),
      typeKey: isSensor ? _sensorTypeKey(blob) : 'pump.type.dash',
      start:
          _time(blob[isSensor ? 'sensor_start' : 'activated_at']) ??
          registeredAt,
      expiresAt: expiresAt,
      registeredAt: registeredAt,
      discardedAt: _time(row['discarded_at']),
      sensorCode: isSensor ? _sensorCode(blob['pairing_code']) : null,
    );
  }

  /// The G7's pairing code as the sensor registration carries it, or null when
  /// there is none to show.
  String? _sensorCode(Object? code) {
    return code is String && code.isNotEmpty ? code : null;
  }

  /// What identifies the physical device across registrations.
  ///
  /// A sensor carries its own resolved key. A pod's `unique_id` is derived from
  /// the controller and is therefore the SAME for every pod this app has ever
  /// activated, so it identifies nothing; its activation moment does, since two
  /// pods are never activated in the same millisecond.
  String _deviceKey(
    bool isSensor,
    Map<String, dynamic> blob,
    Map<String, dynamic> row,
  ) {
    final key = isSensor ? blob['resolved_key'] : blob['activated_at'];
    return key == null ? '${row['id']}' : '$key';
  }

  /// The product-name key, defaulting to the Dexcom G7 the way
  /// [SensorType.fromWireKey] does: it was the only CGM, so a blob written
  /// before multi-sensor support carries no type at all.
  String _sensorTypeKey(Map<String, dynamic> blob) {
    final type = SensorType.fromWireKey(blob['sensor_type'] as String?);
    return type == SensorType.abbottLibre3
        ? 'sensor.type.libre3'
        : 'sensor.type.g7';
  }

  Map<String, dynamic> _blob(Object? data) {
    if (data is! String) {
      return const {};
    }
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  DateTime? _time(Object? millis) {
    return millis is num
        ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
        : null;
  }
}
