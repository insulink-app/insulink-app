import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/protocol/device_info.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_attributes.dart';
import 'package:insulink/src/sensor/info/sensor_info_section.dart';

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

  @override
  Widget build(BuildContext context) {
    final sections = SensorAttributes(
      info: info,
      sensorStart: sensorStart,
      state: state,
      age: age,
      lastUpdate: lastUpdate,
      localize: (key) => Locales.string(context, key),
    ).build();
    return SensorSectionList(sections: sections);
  }
}
