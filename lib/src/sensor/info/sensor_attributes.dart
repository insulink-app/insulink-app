import '../../g7/protocol/device_info.dart';

/// One labelled group of sensor attributes (status / device / session / battery)
/// with its already-formatted rows (label → value).
typedef SensorSection = ({
  String titleKey,
  List<MapEntry<String, String>> items,
});

/// Assembles the grouped, formatted attribute rows shown by `SensorInfo` from
/// the raw [G7DeviceInfo]. Pure data assembly (no widgets); [localize] resolves
/// a locale key to display text so this stays free of `BuildContext`.
class SensorAttributes {
  SensorAttributes({
    required this.info,
    required this.sensorStart,
    required this.state,
    required this.age,
    required this.lastUpdate,
    required this.localize,
  });

  final G7DeviceInfo info;
  final DateTime? sensorStart;
  final int? state;
  final int? age;
  final DateTime? lastUpdate;
  final String Function(String key) localize;

  /// All non-empty sections, in display order.
  List<SensorSection> build() {
    final sections = <SensorSection>[
      (titleKey: 'sensor.info.status', items: _status()),
      (titleKey: 'sensor.info.device', items: _device()),
      (titleKey: 'sensor.info.session', items: _session()),
      (titleKey: 'sensor.info.battery', items: _battery()),
    ];
    return sections.where((section) => section.items.isNotEmpty).toList();
  }

  /// Append a row when the value is present and non-empty.
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
    _add(rows, 'sensor.field.state', _stateLabel());
    if (lastUpdate != null) {
      _add(rows, 'sensor.field.last_reading', _dateTimeWithSeconds(lastUpdate));
    }
    _add(rows, 'sensor.field.started', _dateTime(sensorStart));
    _add(rows, 'sensor.field.expires', _expiry());
    _add(rows, 'sensor.field.age', _duration(_effectiveAge));
    _addCalibration(rows);
    return rows;
  }

  void _addCalibration(List<MapEntry<String, String>> rows) {
    if (!info.hasCalibrationBounds) {
      return;
    }
    _add(
      rows,
      'sensor.field.calibration',
      localize(
        info.calibrationsPermitted!
            ? 'sensor.value.cal_allowed'
            : 'sensor.value.cal_not_allowed',
      ),
    );
    if ((info.lastCalBgValue ?? 0) > 0) {
      _add(rows, 'sensor.field.last_cal_bg', '${info.lastCalBgValue} mg/dL');
    }
  }

  List<MapEntry<String, String>> _device() {
    final rows = <MapEntry<String, String>>[];
    _add(rows, 'sensor.field.firmware', info.firmware);
    _add(rows, 'sensor.field.software', info.softwareNumber?.toString());
    _add(rows, 'sensor.field.hardware', info.hardwareVersion?.toString());
    _add(rows, 'sensor.field.algorithm', _hex(info.algorithmVersion));
    _add(rows, 'sensor.field.silicon', _hex(info.siliconVersion));
    _add(rows, 'sensor.field.serial', info.serialNumber);
    return rows;
  }

  List<MapEntry<String, String>> _session() {
    final rows = <MapEntry<String, String>>[];
    _add(rows, 'sensor.field.session', _duration(info.sessionLengthSec));
    _add(rows, 'sensor.field.warmup', _duration(info.warmupSec));
    _add(rows, 'sensor.field.max_days', info.maxLifetimeDays?.toString());
    return rows;
  }

  List<MapEntry<String, String>> _battery() {
    final rows = <MapEntry<String, String>>[];
    if (info.batteryVoltageA == null) {
      return rows;
    }
    _add(
      rows,
      'sensor.field.voltage',
      '${info.batteryVoltageA}/${info.batteryVoltageB} mV',
    );
    _add(rows, 'sensor.field.runtime', '${info.runtimeDays}d');
    _add(rows, 'sensor.field.temperature', '${info.temperatureC} °C');
    return rows;
  }

  String? _stateLabel() {
    if (state == null) {
      return null;
    }
    final key = g7AlgorithmStateKey(state!);
    return key != null ? localize(key) : '0x${state!.toRadixString(16)}';
  }

  String? _expiry() {
    if (sensorStart == null || info.sessionLengthSec == null) {
      return null;
    }
    final expiry = sensorStart!.add(Duration(seconds: info.sessionLengthSec!));
    final remaining = expiry.difference(DateTime.now());
    final remainingLabel = remaining.isNegative
        ? localize('sensor.value.expired')
        : 'in ${remaining.inDays}d ${remaining.inHours % 24}h';
    return '${_dateTime(expiry)} ($remainingLabel)';
  }

  int? get _effectiveAge {
    if (age != null) {
      return age;
    }
    if (sensorStart == null) {
      return null;
    }
    return DateTime.now().difference(sensorStart!).inSeconds;
  }

  String? _hex(int? value) =>
      value != null ? '0x${value.toRadixString(16)}' : null;

  String _duration(int? secs) {
    if (secs == null) {
      return '—';
    }
    final days = secs ~/ 86400;
    final hours = (secs % 86400) ~/ 3600;
    final minutes = (secs % 3600) ~/ 60;
    if (days > 0) {
      return '${days}d ${hours}h';
    }
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _dateTime(DateTime? time) {
    if (time == null) {
      return '—';
    }
    return '${_two(time.day)}.${_two(time.month)} '
        '${_two(time.hour)}:${_two(time.minute)}';
  }

  /// Like [_dateTime] but with seconds, for the precise last-reception time.
  String _dateTimeWithSeconds(DateTime? time) {
    if (time == null) {
      return '—';
    }
    return '${_dateTime(time)}:${_two(time.second)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
