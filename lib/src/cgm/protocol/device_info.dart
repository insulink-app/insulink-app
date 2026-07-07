import 'dart:typed_data';

// (de)serialization for caching lives in this file; see toJson/fromJson below.

/// Locale key for a G7 algorithm/calibration state (Dexcom `AlgorithmState`),
/// or null for an unknown state (the caller formats the raw hex value).
String? g7AlgorithmStateKey(int state) {
  switch (state) {
    case 0x00:
      return 'sensor.state.none';
    case 0x01:
      return 'sensor.state.session_stopped';
    case 0x02:
      return 'sensor.state.warmup';
    case 0x03:
      return 'sensor.state.excess_noise';
    case 0x04:
      return 'sensor.state.bg1_needed';
    case 0x05:
      return 'sensor.state.bg2_needed';
    case 0x06:
      return 'sensor.state.ok';
    case 0x07:
      return 'sensor.state.needs_calibration';
    case 0x08:
    case 0x09:
    case 0x0A:
      return 'sensor.state.calibration_error';
    case 0x0B:
    case 0x0C:
      return 'sensor.state.sensor_failed';
    case 0x0D:
      return 'sensor.state.out_of_calibration';
    case 0x0E:
      return 'sensor.state.calibration_requested';
    case 0x0F:
      return 'sensor.state.session_expired';
    case 0x10:
    case 0x11:
      return 'sensor.state.session_failed';
    case 0x12:
      return 'sensor.state.temporary_issue';
    case 0x13:
      return 'sensor.state.sensor_declining';
    default:
      return null;
  }
}

/// Accumulates sensor metadata from the control-characteristic responses:
///   0x4A transmitterVersion (firmware, software #, silicon, serial)
///   0x52 transmitterVersionExtended (session/warmup length, algo/hw version)
///   0x22 batteryStatus (voltages, runtime, temperature)
/// Layouts from DiaBLE's DexcomG7 (LoopKit/G7SensorKit-derived).
class G7DeviceInfo {
  String? firmware;
  int? softwareNumber;
  int? siliconVersion;
  String? serialNumber;

  /// Total session length in seconds (includes the ~12 h grace period).
  int? sessionLengthSec;
  int? warmupSec;
  int? algorithmVersion;
  int? hardwareVersion;
  int? maxLifetimeDays;

  int? batteryVoltageA;
  int? batteryVoltageB;
  int? runtimeDays;
  int? temperatureC;

  // --- calibration bounds (control opcode 0x32) -----------------------------
  // Read-only status the sensor reports about (optional) BG calibration. Layout
  // verified against DiaBLE's DexcomG7 calibrationBounds parse. We do NOT yet
  // send the 0x34 calibrate write — its payload isn't verified in any open
  // source (see docs/PROTOCOL.md). This read tells us whether/when a calibration
  // would be accepted and the last BG that was entered.
  /// Whether the sensor currently accepts a BG calibration.
  bool? calibrationsPermitted;

  /// The last calibration BG value (mg/dL); 0 / null means none entered yet.
  int? lastCalBgValue;

  /// Seconds-since-session-start of the last calibration (0 = none).
  int? lastCalTimeSec;

  /// Raw `CalibrationProcessingStatus` byte (kept raw — the enum mapping isn't
  /// verified in the open references).
  int? calProcessingStatus;

  /// Explicit default constructor (required once a factory ctor is declared).
  G7DeviceInfo();

  /// True once ANY metadata field has been parsed, so partial info (e.g. a
  /// battery or session reply that arrives before the version reply) is still
  /// persisted and shown rather than being dropped until firmware/serial land.
  bool get hasAny =>
      firmware != null ||
      serialNumber != null ||
      sessionLengthSec != null ||
      warmupSec != null ||
      algorithmVersion != null ||
      hardwareVersion != null ||
      maxLifetimeDays != null ||
      batteryVoltageA != null ||
      calibrationsPermitted != null;

  /// True once a 0x32 calibrationBounds response has been parsed.
  bool get hasCalibrationBounds => calibrationsPermitted != null;

  Map<String, dynamic> toJson() => {
    'firmware': firmware,
    'sw': softwareNumber,
    'silicon': siliconVersion,
    'serial': serialNumber,
    'session': sessionLengthSec,
    'warmup': warmupSec,
    'algo': algorithmVersion,
    'hw': hardwareVersion,
    'maxDays': maxLifetimeDays,
    'battA': batteryVoltageA,
    'battB': batteryVoltageB,
    'runtime': runtimeDays,
    'temp': temperatureC,
    'calPermitted': calibrationsPermitted,
    'calLastBg': lastCalBgValue,
    'calLastTime': lastCalTimeSec,
    'calProc': calProcessingStatus,
  };

  factory G7DeviceInfo.fromJson(Map<String, dynamic> json) {
    final info = G7DeviceInfo();
    info.firmware = json['firmware'] as String?;
    info.softwareNumber = json['sw'] as int?;
    info.siliconVersion = json['silicon'] as int?;
    info.serialNumber = json['serial'] as String?;
    info.sessionLengthSec = json['session'] as int?;
    info.warmupSec = json['warmup'] as int?;
    info.algorithmVersion = json['algo'] as int?;
    info.hardwareVersion = json['hw'] as int?;
    info.maxLifetimeDays = json['maxDays'] as int?;
    info.batteryVoltageA = json['battA'] as int?;
    info.batteryVoltageB = json['battB'] as int?;
    info.runtimeDays = json['runtime'] as int?;
    info.temperatureC = json['temp'] as int?;
    info.calibrationsPermitted = json['calPermitted'] as bool?;
    info.lastCalBgValue = json['calLastBg'] as int?;
    info.lastCalTimeSec = json['calLastTime'] as int?;
    info.calProcessingStatus = json['calProc'] as int?;
    return info;
  }

  /// Dispatch a control-characteristic reply to its parser. Returns true if
  /// [data] was a recognized metadata message.
  bool applyControl(Uint8List data) {
    if (data.length < 2) {
      return false;
    }
    final bytes = ByteData.sublistView(data);
    switch (data[0]) {
      case 0x4A:
        return _applyVersion(data, bytes);
      case 0x52:
        return _applyVersionExtended(data, bytes);
      case 0x22:
        return _applyBattery(data, bytes);
      case 0x32:
        return _applyCalibrationBounds(data, bytes);
      default:
        return false;
    }
  }

  /// transmitterVersion (0x4A, 20 bytes): firmware, software #, silicon, and the
  /// 6-byte little-endian serial.
  bool _applyVersion(Uint8List data, ByteData bytes) {
    if (data.length < 20) {
      return false;
    }
    firmware = '${data[2]}.${data[3]}.${data[4]}.${data[5]}';
    softwareNumber = bytes.getUint32(6, Endian.little);
    siliconVersion = bytes.getUint32(10, Endian.little);
    var serial = 0;
    for (var index = 0; index < 6; index++) {
      serial |= data[14 + index] << (8 * index);
    }
    serialNumber = serial.toString();
    return true;
  }

  /// transmitterVersionExtended (0x52, 15 bytes): session/warmup length and the
  /// algorithm/hardware versions.
  bool _applyVersionExtended(Uint8List data, ByteData bytes) {
    if (data.length < 15) {
      return false;
    }
    sessionLengthSec = bytes.getUint32(2, Endian.little);
    warmupSec = bytes.getUint16(6, Endian.little);
    algorithmVersion = bytes.getUint32(8, Endian.little);
    hardwareVersion = data[12];
    maxLifetimeDays = bytes.getUint16(13, Endian.little);
    return true;
  }

  /// batteryStatus (0x22): the two voltages, runtime days and temperature.
  bool _applyBattery(Uint8List data, ByteData bytes) {
    if (data.length < 8) {
      return false;
    }
    batteryVoltageA = bytes.getUint16(2, Endian.little);
    batteryVoltageB = bytes.getUint16(4, Endian.little);
    runtimeDays = data[6];
    temperatureC = bytes.getInt8(7);
    return true;
  }

  /// calibrationBounds (0x32, 20 bytes) — read-only calibration status.
  /// data[1]=status, [2]=sessionNumber, [3..6]=sessionSignature,
  /// [7..8]=lastBGValue, [9..12]=lastCalibrationTime, [13]=processingStatus,
  /// [14]=calibrationsPermitted, [15]=lastBGDisplay, [16..19]=lastProcessingUpdate.
  bool _applyCalibrationBounds(Uint8List data, ByteData bytes) {
    if (data.length < 20) {
      return false;
    }
    lastCalBgValue = bytes.getUint16(7, Endian.little);
    lastCalTimeSec = bytes.getUint32(9, Endian.little);
    calProcessingStatus = data[13];
    calibrationsPermitted = data[14] != 0;
    return true;
  }
}
