import 'package:flutter/material.dart';
import 'package:insulink/src/g7/device_info.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

/// Everything the sensor reports, grouped into labelled sections (status,
/// device, session, battery) with one value per row.
class SensorInfo extends StatelessWidget {
  const SensorInfo({
    super.key,
    required this.info,
    required this.sensorStart,
    required this.state,
    required this.age,
    required this.lastUpdate,
  });

  final G7DeviceInfo info;
  final DateTime? sensorStart;
  final int? state;
  final int? age;

  /// Wall-clock time the latest reading was received (shown on this page now
  /// that the overview only counts down to the next one).
  final DateTime? lastUpdate;

  static String _dur(int? secs) {
    if (secs == null) return '—';
    final d = secs ~/ 86400,
        h = (secs % 86400) ~/ 3600,
        m = (secs % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static String _dt(DateTime? t) {
    if (t == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// Like [_dt] but with seconds, for the precise last-reception time.
  static String _dts(DateTime? t) {
    if (t == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_dt(t)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => Locales.string(context, key);

    final status = <MapEntry<String, String>>[];
    final device = <MapEntry<String, String>>[];
    final session = <MapEntry<String, String>>[];
    final battery = <MapEntry<String, String>>[];

    // [labelKey] is a locale key resolved here; [v] is the (already formatted)
    // value to show.
    void add(List<MapEntry<String, String>> into, String labelKey, String? v) {
      if (v != null && v.isNotEmpty) into.add(MapEntry(t(labelKey), v));
    }

    // Status
    if (state != null) {
      final key = g7AlgorithmStateKey(state!);
      add(
        status,
        'sensor.field.state',
        key != null ? t(key) : '0x${state!.toRadixString(16)}',
      );
    }
    if (lastUpdate != null) {
      add(status, 'sensor.field.last_reading', _dts(lastUpdate));
    }
    add(status, 'sensor.field.started', _dt(sensorStart));
    if (sensorStart != null && info.sessionLengthSec != null) {
      final expiry = sensorStart!.add(
        Duration(seconds: info.sessionLengthSec!),
      );
      final rem = expiry.difference(DateTime.now());
      final remStr = rem.isNegative
          ? t('sensor.value.expired')
          : 'in ${rem.inDays}d ${rem.inHours % 24}h';
      add(status, 'sensor.field.expires', '${_dt(expiry)} ($remStr)');
    }
    final effAge =
        age ??
        (sensorStart != null
            ? DateTime.now().difference(sensorStart!).inSeconds
            : null);
    add(status, 'sensor.field.age', _dur(effAge));
    if (info.hasCalibrationBounds) {
      add(
        status,
        'sensor.field.calibration',
        info.calibrationsPermitted!
            ? t('sensor.value.cal_allowed')
            : t('sensor.value.cal_not_allowed'),
      );
      if ((info.lastCalBgValue ?? 0) > 0) {
        add(status, 'sensor.field.last_cal_bg', '${info.lastCalBgValue} mg/dL');
      }
    }

    // Device
    add(device, 'sensor.field.firmware', info.firmware);
    add(device, 'sensor.field.software', info.softwareNumber?.toString());
    add(device, 'sensor.field.hardware', info.hardwareVersion?.toString());
    add(
      device,
      'sensor.field.algorithm',
      info.algorithmVersion != null
          ? '0x${info.algorithmVersion!.toRadixString(16)}'
          : null,
    );
    add(
      device,
      'sensor.field.silicon',
      info.siliconVersion != null
          ? '0x${info.siliconVersion!.toRadixString(16)}'
          : null,
    );
    add(device, 'sensor.field.serial', info.serialNumber);

    // Session
    add(session, 'sensor.field.session', _dur(info.sessionLengthSec));
    add(session, 'sensor.field.warmup', _dur(info.warmupSec));
    add(session, 'sensor.field.max_days', info.maxLifetimeDays?.toString());

    // Battery
    if (info.batteryVoltageA != null) {
      add(
        battery,
        'sensor.field.voltage',
        '${info.batteryVoltageA}/${info.batteryVoltageB} mV',
      );
      add(battery, 'sensor.field.runtime', '${info.runtimeDays}d');
      add(battery, 'sensor.field.temperature', '${info.temperatureC} °C');
    }

    final sections = <Widget>[
      if (status.isNotEmpty) _Section('sensor.info.status', status),
      if (device.isNotEmpty) _Section('sensor.info.device', device),
      if (session.isNotEmpty) _Section('sensor.info.session', session),
      if (battery.isNotEmpty) _Section('sensor.info.battery', battery),
    ];

    if (sections.isEmpty) {
      return Center(child: LocaleText('sensor.info.empty'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          sections[i],
        ],
      ],
    );
  }
}

/// A titled card listing one [_InfoRow] per value.
class _Section extends StatelessWidget {
  const _Section(this.titleKey, this.items);

  final String titleKey;
  final List<MapEntry<String, String>> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocaleText(
            titleKey,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: scheme.onSurface.withValues(alpha: 0.06),
              ),
            _InfoRow(label: items[i].key, value: items[i].value),
          ],
        ],
      ),
    );
  }
}

/// One label/value line: label muted on the left, value emphasised on the right.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
