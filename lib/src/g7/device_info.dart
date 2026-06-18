import 'dart:typed_data';

// (de)serialization for caching lives in this file; see toJson/fromJson below.

/// G7 algorithm/calibration state (Dexcom `AlgorithmState`).
String g7AlgorithmState(int v) {
  switch (v) {
    case 0x00:
      return 'none';
    case 0x01:
      return 'session stopped';
    case 0x02:
      return 'warmup';
    case 0x03:
      return 'excess noise';
    case 0x04:
      return '1st of 2 BGs needed';
    case 0x05:
      return '2nd of 2 BGs needed';
    case 0x06:
      return 'OK';
    case 0x07:
      return 'needs calibration';
    case 0x08:
    case 0x09:
    case 0x0A:
      return 'calibration error';
    case 0x0B:
    case 0x0C:
      return 'sensor failed';
    case 0x0D:
      return 'out of calibration';
    case 0x0E:
      return 'calibration requested';
    case 0x0F:
      return 'session expired';
    case 0x10:
    case 0x11:
      return 'session failed';
    case 0x12:
      return 'temporary issue';
    case 0x13:
      return 'sensor declining';
    default:
      return 'state 0x${v.toRadixString(16)}';
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

  /// Explicit default constructor (required once a factory ctor is declared).
  G7DeviceInfo();

  bool get hasAny =>
      firmware != null || serialNumber != null || sessionLengthSec != null;

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
      default:
        return false;
    }
  }
}
