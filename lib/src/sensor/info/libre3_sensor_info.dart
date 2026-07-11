import 'package:flutter/material.dart';

import '../../cgm/cgm_connection.dart';
import '../../localization/locales.dart';
import 'sensor_attributes.dart';
import 'sensor_format.dart';
import 'sensor_info_section.dart';

/// The FreeStyle Libre 3 counterpart to [SensorInfo]: the G7 attribute builder
/// reads a [G7DeviceInfo] the Libre never produces, so this assembles the
/// Libre-specific rows (activation MAC, session clock, and the extra fields the
/// one-minute reading carries — predicted glucose, trend rate, body temperature)
/// and renders them through the shared [SensorSectionList].
class Libre3SensorInfo extends StatelessWidget {
  const Libre3SensorInfo({
    super.key,
    required this.mac,
    required this.sensorStart,
    required this.lastUpdate,
    required this.latest,
  });

  final String? mac;
  final DateTime? sensorStart;
  final DateTime? lastUpdate;
  final CgmReading? latest;

  @override
  Widget build(BuildContext context) {
    final sections = Libre3Attributes(
      mac: mac,
      sensorStart: sensorStart,
      lastUpdate: lastUpdate,
      latest: latest,
      localize: (key) => Locales.string(context, key),
    ).build();
    return SensorSectionList(sections: sections);
  }
}

/// Builds the grouped Libre 3 attribute rows (pure data assembly, no widgets).
class Libre3Attributes {
  Libre3Attributes({
    required this.mac,
    required this.sensorStart,
    required this.lastUpdate,
    required this.latest,
    required this.localize,
  });

  final String? mac;
  final DateTime? sensorStart;
  final DateTime? lastUpdate;
  final CgmReading? latest;
  final String Function(String key) localize;

  /// Libre 3 warm-up before the first reading (60 min, fixed).
  static const int _warmupSec = 3600;
  int get _sessionLengthSec => SensorType.abbottLibre3.sessionLengthSec;

  List<SensorSection> build() {
    final sections = <SensorSection>[
      (titleKey: 'sensor.info.status', items: _status()),
      (titleKey: 'sensor.info.live', items: _live()),
      (titleKey: 'sensor.info.device', items: _device()),
      (titleKey: 'sensor.info.session', items: _session()),
    ];
    return sections.where((section) => section.items.isNotEmpty).toList();
  }

  void _add(
    List<MapEntry<String, String>> into,
    String labelKey,
    String? value,
  ) {
    if (value != null && value.isNotEmpty) {
      into.add(MapEntry(localize(labelKey), value));
    }
  }

  List<MapEntry<String, String>> _status() {
    final rows = <MapEntry<String, String>>[];
    if (lastUpdate != null) {
      _add(rows, 'sensor.field.last_reading', formatSensorDateTime(lastUpdate));
    }
    _add(rows, 'sensor.field.started', formatSensorDateTime(sensorStart));
    _add(rows, 'sensor.field.expires', _expiry());
    _add(rows, 'sensor.field.age', formatSensorDuration(_ageSec));
    return rows;
  }

  List<MapEntry<String, String>> _live() {
    final reading = latest;
    if (reading == null) {
      return const [];
    }
    final rows = <MapEntry<String, String>>[];
    if (reading.predictedMgDl > 0) {
      _add(rows, 'sensor.field.predicted', '${reading.predictedMgDl} mg/dL');
    }
    _add(rows, 'sensor.field.trend', _trend(reading.trendMgDlPerMin));
    _add(
      rows,
      'sensor.field.temperature',
      _temperature(reading.temperatureCentiC),
    );
    return rows;
  }

  List<MapEntry<String, String>> _device() {
    final rows = <MapEntry<String, String>>[];
    _add(rows, 'sensor.field.mac', mac);
    return rows;
  }

  List<MapEntry<String, String>> _session() {
    return [
      MapEntry(
        localize('sensor.field.session'),
        formatSensorDuration(_sessionLengthSec),
      ),
      MapEntry(
        localize('sensor.field.warmup'),
        formatSensorDuration(_warmupSec),
      ),
    ];
  }

  int? get _ageSec {
    if (latest != null) {
      return latest!.secsSinceStart;
    }
    if (sensorStart == null) {
      return null;
    }
    return DateTime.now().difference(sensorStart!).inSeconds;
  }

  String? _expiry() {
    if (sensorStart == null) {
      return null;
    }
    final expiry = sensorStart!.add(Duration(seconds: _sessionLengthSec));
    final remaining = expiry.difference(DateTime.now());
    final label = remaining.isNegative
        ? localize('sensor.value.expired')
        : 'in ${remaining.inDays}d ${remaining.inHours % 24}h';
    return '${formatSensorDateTime(expiry)} ($label)';
  }

  String _trend(double perMin) =>
      '${perMin >= 0 ? '+' : ''}${perMin.toStringAsFixed(1)} mg/dL/min';

  String? _temperature(int? centiC) =>
      centiC == null ? null : '${(centiC / 100).toStringAsFixed(1)} °C';
}
