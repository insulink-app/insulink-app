import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// What the band's standard Device Information service (0x180A) tells in the
/// clear. The Fitbit Air leaves hardware/software revision empty and System
/// ID/PnP ID zeroed, so only these three carry anything.
@immutable
class BandDeviceInfo {
  const BandDeviceInfo({this.model, this.serial, this.firmware});

  static final Guid _service = Guid('180A');
  static final Guid _model = Guid('2A24');
  static final Guid _serial = Guid('2A25');
  static final Guid _firmware = Guid('2A26');

  final String? model;
  final String? serial;
  final String? firmware;

  /// Reads the strings off an already discovered [device], or null when it has
  /// no Device Information service. Each read is best-effort: one failing
  /// characteristic leaves its field null instead of losing the others.
  static Future<BandDeviceInfo?> read(BluetoothDevice device) async {
    final service = device.servicesList
        .where((candidate) => candidate.uuid == _service)
        .firstOrNull;
    if (service == null) {
      return null;
    }
    return BandDeviceInfo(
      model: await _readString(service, _model),
      serial: await _readString(service, _serial),
      firmware: await _readString(service, _firmware),
    );
  }

  /// One characteristic as UTF-8, or null when absent, empty or unreadable.
  static Future<String?> _readString(
    BluetoothService service,
    Guid uuid,
  ) async {
    final characteristic = service.characteristics
        .where((candidate) => candidate.uuid == uuid)
        .firstOrNull;
    try {
      final bytes = await characteristic?.read();
      final text = bytes == null ? '' : utf8.decode(bytes).trim();
      return text.isEmpty ? null : text;
    } catch (error) {
      debugPrint('[fitbit-hr] device info $uuid failed: $error');
      return null;
    }
  }

  static BandDeviceInfo? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    return BandDeviceInfo(
      model: json['model'] as String?,
      serial: json['serial'] as String?,
      firmware: json['firmware'] as String?,
    );
  }

  Map<String, String?> toJson() => {
    'model': model,
    'serial': serial,
    'firmware': firmware,
  };
}
