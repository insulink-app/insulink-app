import 'dart:convert';

import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/demo/demo_pump.dart';
import 'package:insulink/src/demo/demo_sensor.dart';

/// The sensors and pods the demo account has held, in the rows
/// `/sensor/history/` and `/pump/history/` answer with, so both history pages
/// have a month to show.
///
/// Newest first back from the devices the demo is running. Most ran their full
/// life; one sensor came off early and was discarded, one was a Libre 3, and one
/// pod was replaced before its time, so every state the page draws turns up.
class DemoDevices {
  DemoDevices(this.now);

  final DateTime now;

  static const int sensorCount = 4;
  static const int podCount = 10;
  static const Duration podLife = Duration(hours: 72);
  static const Duration podExpiry = Duration(hours: 80);

  /// Days each earlier sensor was worn (index 0 is the one before the current),
  /// null for a full session.
  static const List<int?> sensorWornDays = [null, 3, null];

  /// Which earlier sensor was a FreeStyle Libre 3.
  static const int librePosition = 2;

  /// Which earlier pod came off after a single day.
  static const int shortPodPosition = 4;

  List<Map<String, Object>> get sensors {
    var start = now.subtract(DemoSensor.age);
    final rows = [_sensor(0, SensorType.dexcomG7, start, DemoSensor.key, null)];
    for (var position = 0; position < sensorCount - 1; position++) {
      final type = position == librePosition
          ? SensorType.abbottLibre3
          : SensorType.dexcomG7;
      final worn = sensorWornDays[position];
      start = start.subtract(
        worn == null
            ? Duration(seconds: type.sessionLengthSec)
            : Duration(days: worn),
      );
      final discarded = worn == null ? null : start.add(Duration(days: worn));
      rows.add(
        _sensor(position + 1, type, start, 'demo-sensor-$position', discarded),
      );
    }
    return rows;
  }

  List<Map<String, Object>> get pumps {
    var activated = now.subtract(DemoPump.age);
    final rows = [_pod(0, activated, null)];
    for (var position = 1; position < podCount; position++) {
      final short = position == shortPodPosition;
      activated = activated.subtract(short ? const Duration(days: 1) : podLife);
      rows.add(
        _pod(
          position,
          activated,
          short ? activated.add(const Duration(days: 1)) : null,
        ),
      );
    }
    return rows;
  }

  Map<String, Object> _sensor(
    int id,
    SensorType type,
    DateTime start,
    String key,
    DateTime? discarded,
  ) => _row(
    id: id,
    start: start,
    expires: start.add(Duration(seconds: type.sessionLengthSec)),
    discarded: discarded,
    data: {
      'sensor_start': start.millisecondsSinceEpoch,
      'resolved_key': key,
      'sensor_type': type.wireKey,
    },
  );

  Map<String, Object> _pod(int id, DateTime activated, DateTime? discarded) =>
      _row(
        id: id,
        start: activated,
        expires: activated.add(podExpiry),
        discarded: discarded,
        data: {'activated_at': activated.millisecondsSinceEpoch},
      );

  Map<String, Object> _row({
    required int id,
    required DateTime start,
    required DateTime expires,
    required DateTime? discarded,
    required Map<String, Object> data,
  }) => {
    'id': id,
    'registered_at': start
        .add(const Duration(minutes: 3))
        .millisecondsSinceEpoch,
    'expires_at': expires.millisecondsSinceEpoch,
    'discarded_at': ?discarded?.millisecondsSinceEpoch,
    'data': jsonEncode(data),
  };
}
