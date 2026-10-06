import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/protocol/device_info.dart';
import 'package:insulink/src/sensor/info/sensor_attributes.dart';

void main() {
  String localize(String key) => key;

  Map<String, String> rowsOf(List<SensorSection> sections, String titleKey) => {
    for (final section in sections)
      if (section.titleKey == titleKey)
        for (final row in section.items) row.key: row.value,
  };

  test('an empty device info drops the sections that need a reading', () {
    final sections = SensorAttributes(
      info: G7DeviceInfo(),
      sensorStart: null,
      state: null,
      age: null,
      lastUpdate: null,
      localize: localize,
    ).build();

    expect(
      sections.map((section) => section.titleKey),
      ['sensor.info.status', 'sensor.info.session'],
    );
    expect(rowsOf(sections, 'sensor.info.status'), {
      'sensor.field.started': '—',
      'sensor.field.age': '—',
    });
    expect(rowsOf(sections, 'sensor.info.device'), isEmpty);
    expect(rowsOf(sections, 'sensor.info.battery'), isEmpty);
  });

  test('the device section formats versions as hex and skips absent fields', () {
    final info = G7DeviceInfo()
      ..firmware = '1.2.3'
      ..softwareNumber = 42
      ..algorithmVersion = 0xAB
      ..siliconVersion = 0x10
      ..serialNumber = 'DX1234';

    final device = rowsOf(
      SensorAttributes(
        info: info,
        sensorStart: null,
        state: null,
        age: null,
        lastUpdate: null,
        localize: localize,
      ).build(),
      'sensor.info.device',
    );

    expect(device['sensor.field.firmware'], '1.2.3');
    expect(device['sensor.field.software'], '42');
    expect(device['sensor.field.algorithm'], '0xab');
    expect(device['sensor.field.silicon'], '0x10');
    expect(device['sensor.field.serial'], 'DX1234');
    expect(device.containsKey('sensor.field.hardware'), isFalse);
  });

  test('a known state is localized, an unknown one shown as raw hex', () {
    SensorAttributes attributesFor(int state) => SensorAttributes(
      info: G7DeviceInfo(),
      sensorStart: null,
      state: state,
      age: null,
      lastUpdate: null,
      localize: localize,
    );

    expect(
      rowsOf(attributesFor(0x06).build(), 'sensor.info.status'),
      containsPair('sensor.field.state', 'sensor.state.ok'),
    );
    expect(
      rowsOf(attributesFor(0x7F).build(), 'sensor.info.status'),
      containsPair('sensor.field.state', '0x7f'),
    );
  });

  test('the expiry row carries the remaining time, or "expired" when past', () {
    final info = G7DeviceInfo()..sessionLengthSec = 3 * 86400;

    final running = rowsOf(
      SensorAttributes(
        info: info,
        sensorStart: DateTime.now().subtract(const Duration(days: 1)),
        state: null,
        age: null,
        lastUpdate: null,
        localize: localize,
      ).build(),
      'sensor.info.status',
    );
    final expired = rowsOf(
      SensorAttributes(
        info: info,
        sensorStart: DateTime.now().subtract(const Duration(days: 9)),
        state: null,
        age: null,
        lastUpdate: null,
        localize: localize,
      ).build(),
      'sensor.info.status',
    );

    expect(running['sensor.field.expires'], contains('in 1d'));
    expect(expired['sensor.field.expires'], contains('sensor.value.expired'));
    expect(running['sensor.field.age'], '1 sensor.unit.day 0 h');
  });

  test('calibration rows appear only once bounds were read', () {
    final withBounds = G7DeviceInfo()
      ..calibrationsPermitted = true
      ..lastCalBgValue = 118;

    final rows = rowsOf(
      SensorAttributes(
        info: withBounds,
        sensorStart: null,
        state: null,
        age: null,
        lastUpdate: null,
        localize: localize,
      ).build(),
      'sensor.info.status',
    );

    expect(rows['sensor.field.calibration'], 'sensor.value.cal_allowed');
    expect(rows['sensor.field.last_cal_bg'], '118 mg/dL');
  });

  test('the battery section is skipped without a voltage reading', () {
    final drained = G7DeviceInfo()
      ..batteryVoltageA = 300
      ..batteryVoltageB = 290
      ..runtimeDays = 12
      ..temperatureC = 33;

    final rows = rowsOf(
      SensorAttributes(
        info: drained,
        sensorStart: null,
        state: null,
        age: null,
        lastUpdate: null,
        localize: localize,
      ).build(),
      'sensor.info.battery',
    );

    expect(rows['sensor.field.voltage'], '300/290 mV');
    expect(rows['sensor.field.runtime'], '12d');
    expect(rows['sensor.field.temperature'], '33 °C');

    final none = SensorAttributes(
      info: G7DeviceInfo()..runtimeDays = 12,
      sensorStart: null,
      state: null,
      age: null,
      lastUpdate: null,
      localize: localize,
    ).build();
    expect(rowsOf(none, 'sensor.info.battery'), isEmpty);
  });

  test('the last reception time is shown down to the second', () {
    final rows = rowsOf(
      SensorAttributes(
        info: G7DeviceInfo(),
        sensorStart: null,
        state: null,
        age: 90,
        lastUpdate: DateTime(2026, 7, 9, 16, 4, 5),
        localize: localize,
      ).build(),
      'sensor.info.status',
    );

    expect(rows['sensor.field.last_reading'], '09.07., 16:04:05');
    expect(rows['sensor.field.age'], '1 min');
  });

  test('the session section reports session, warmup and max lifetime', () {
    final info = G7DeviceInfo()
      ..sessionLengthSec = 10 * 86400 + 12 * 3600
      ..warmupSec = 30 * 60
      ..maxLifetimeDays = 10;

    final rows = rowsOf(
      SensorAttributes(
        info: info,
        sensorStart: null,
        state: null,
        age: null,
        lastUpdate: null,
        localize: localize,
      ).build(),
      'sensor.info.session',
    );

    expect(rows['sensor.field.session'], '10 d 12 h');
    expect(rows['sensor.field.warmup'], '30 min');
    expect(rows['sensor.field.max_days'], '10');
  });
}
