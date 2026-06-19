import 'dart:typed_data';

// (de)serialization for caching lives in this file; see toJson/fromJson below.

/// Locale key for a G7 algorithm/calibration state (Dexcom `AlgorithmState`),
/// or null for an unknown state (the caller formats the raw hex value).
String? g7AlgorithmStateKey(int v) {
  switch (v) {
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

  bool get hasAny =>
      firmware != null || serialNumber != null || sessionLengthSec != null;

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

  factory G7DeviceInfo.fromJson(Map<String, dynamic> j) {
    final i = G7DeviceInfo();
    i.firmware = j['firmware'] as String?;
    i.softwareNumber = j['sw'] as int?;
    i.siliconVersion = j['silicon'] as int?;
    i.serialNumber = j['serial'] as String?;
    i.sessionLengthSec = j['session'] as int?;
    i.warmupSec = j['warmup'] as int?;
    i.algorithmVersion = j['algo'] as int?;
    i.hardwareVersion = j['hw'] as int?;
    i.maxLifetimeDays = j['maxDays'] as int?;
    i.batteryVoltageA = j['battA'] as int?;
    i.batteryVoltageB = j['battB'] as int?;
    i.runtimeDays = j['runtime'] as int?;
    i.temperatureC = j['temp'] as int?;
    i.calibrationsPermitted = j['calPermitted'] as bool?;
    i.lastCalBgValue = j['calLastBg'] as int?;
    i.lastCalTimeSec = j['calLastTime'] as int?;
    i.calProcessingStatus = j['calProc'] as int?;
    return i;
  }

  /// Returns true if [data] was a recognized metadata message.
  bool applyControl(Uint8List d) {
    if (d.length < 2) return false;
    final bd = ByteData.sublistView(d);
    switch (d[0]) {
      case 0x4A: // transmitterVersion (20 bytes)
        if (d.length < 20) return false;
        firmware = '${d[2]}.${d[3]}.${d[4]}.${d[5]}';
        softwareNumber = bd.getUint32(6, Endian.little);
        siliconVersion = bd.getUint32(10, Endian.little);
        var serial = 0;
        for (var i = 0; i < 6; i++) {
          serial |= d[14 + i] << (8 * i);
        }
        serialNumber = serial.toString();
        return true;
      case 0x52: // transmitterVersionExtended (15 bytes)
        if (d.length < 15) return false;
        sessionLengthSec = bd.getUint32(2, Endian.little);
        warmupSec = bd.getUint16(6, Endian.little);
        algorithmVersion = bd.getUint32(8, Endian.little);
        hardwareVersion = d[12];
        maxLifetimeDays = bd.getUint16(13, Endian.little);
        return true;
      case 0x22: // batteryStatus
        if (d.length < 8) return false;
        batteryVoltageA = bd.getUint16(2, Endian.little);
        batteryVoltageB = bd.getUint16(4, Endian.little);
        runtimeDays = d[6];
        temperatureC = bd.getInt8(7);
        return true;
      case 0x32: // calibrationBounds (20 bytes) — read-only calibration status.
        // d[1]=status, d[2]=sessionNumber, d[3..6]=sessionSignature,
        // d[7..8]=lastBGValue, d[9..12]=lastCalibrationTime,
        // d[13]=processingStatus, d[14]=calibrationsPermitted,
        // d[15]=lastBGDisplay, d[16..19]=lastProcessingUpdateTime.
        if (d.length < 20) return false;
        lastCalBgValue = bd.getUint16(7, Endian.little);
        lastCalTimeSec = bd.getUint32(9, Endian.little);
        calProcessingStatus = d[13];
        calibrationsPermitted = d[14] != 0;
        return true;
      default:
        return false;
    }
  }
}
