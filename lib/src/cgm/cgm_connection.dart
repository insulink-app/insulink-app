import 'dart:typed_data';

/// The CGM hardware this app can read. Persisted (as [wireKey]) so the service
/// isolate knows which [CgmConnection] strategy to build and the pairing UI
/// knows which flow to show.
enum SensorType {
  dexcomG7('dexcom_g7', 'DEXCOM_G7', 300, 907200),
  abbottLibre3('abbott_libre3', 'ABBOTT_LIBRE3', 60, 1209600);

  const SensorType(
    this.wireKey,
    this.backendType,
    this.readingIntervalSec,
    this.sessionLengthSec,
  );

  /// Stable string stored in [CgmStore].
  final String wireKey;

  /// The value the backend's `SensorType` enum expects.
  final String backendType;

  /// Nominal seconds between live readings (G7 ~5 min, Libre 3 ~1 min) — drives
  /// the overview "next reading" countdown.
  final int readingIntervalSec;

  /// Nominal session length (G7 = 10 d + 12 h grace, Libre 3 = 14 d) — the
  /// fallback for the expiry/halftime reminders when the sensor hasn't reported
  /// its own length. Halftime fires at half of this.
  final int sessionLengthSec;

  /// Resolve a persisted [wireKey] back to a type, defaulting to the Dexcom G7
  /// (the original, only sensor — so existing installs keep working).
  static SensorType fromWireKey(String? key) {
    return SensorType.values.firstWhere(
      (type) => type.wireKey == key,
      orElse: () => SensorType.dexcomG7,
    );
  }
}

/// A decoded glucose reading, sensor-agnostic. Both the Dexcom G7 and the
/// FreeStyle Libre 3 decoders produce this so the whole pipeline above the
/// wire layer (persistence, chart, stats, alarms, backend) is shared.
///
/// The clock is always **seconds since the sensor session started**
/// (`secsSinceStart`); the Libre "life count" (minutes since activation) maps to
/// it as `lifeCount * 60`. Glucose is mg/dL for both.
class CgmReading {
  CgmReading({
    required this.secsSinceStart,
    required this.age,
    required this.sequence,
    required this.glucoseMgDl,
    required this.predictedMgDl,
    required this.trendTenths,
    required this.state,
    this.temperatureCentiC,
    this.raw,
  });

  final int secsSinceStart;
  final int age;
  final int sequence;

  /// Glucose in mg/dL, or null when out of the valid range.
  final int? glucoseMgDl;
  final int predictedMgDl;

  /// Trend in 0.1 mg/dL per minute (so 2 == +0.2 mg/dL/min).
  final int trendTenths;

  /// Raw sensor state/status byte (Dexcom algorithm state, or Libre patch
  /// status). Displayed and cached; its meaning is sensor-specific.
  final int state;

  /// Sensor body temperature in 1/100 °C, when the sensor reports it (Libre 3
  /// includes it in each one-minute reading; null for the G7).
  final int? temperatureCentiC;
  final Uint8List? raw;

  double get trendMgDlPerMin => trendTenths / 10.0;

  bool get isValid => glucoseMgDl != null;

  /// Wall-clock time of this reading, given the sensor session start.
  DateTime timestamp(DateTime sessionStart) =>
      sessionStart.add(Duration(seconds: secsSinceStart - age));

  @override
  String toString() => isValid
      ? '$glucoseMgDl mg/dL (${trendMgDlPerMin >= 0 ? '+' : ''}'
            '${trendMgDlPerMin.toStringAsFixed(1)}/min), predicted $predictedMgDl, '
            'age ${age}s, state 0x${state.toRadixString(16)}'
      : 'invalid (state 0x${state.toRadixString(16)}, age ${age}s)';
}

/// Health/recovery cadence the service-isolate watchdog uses. It differs per
/// sensor because the G7 connects, delivers, then drops its link every ~5 min,
/// while the Libre 3 holds a continuous link and streams every ~1 min — so a
/// silence that is normal for one is a fault for the other. Values are
/// deliberately tunable (real radios drift).
class CgmTiming {
  const CgmTiming({
    required this.staleAfter,
    required this.restartAfter,
    required this.processRestartAfter,
    required this.connectStuckAfter,
    required this.reconnectBackoff,
    required this.expectsContinuousLink,
  });

  /// Connected but no reading for this long ⇒ half-open link ⇒ force reconnect.
  final Duration staleAfter;

  /// No reading at all for this long ⇒ restart the service (fresh isolate).
  final Duration restartAfter;

  /// A restart within this window that still yielded no data ⇒ restart the
  /// whole process (the only thing that clears a wedged native BLE stack).
  final Duration processRestartAfter;

  /// A single connect attempt should resolve within this or it's force-reset.
  final Duration connectStuckAfter;

  /// Hold the watchdog's reconnect off this long after a delivery (the sensor
  /// won't advertise again yet; arming early trips Android's scan throttle).
  final Duration reconnectBackoff;

  /// True when the sensor keeps the BLE link up and streams continuously (Libre
  /// 3), false when it connects/delivers/drops each cycle (G7).
  final bool expectsContinuousLink;
}

/// The sensor-agnostic read-pipeline contract the foreground-service isolate
/// drives. Both [G7Connection] and `Libre3Connection` implement it, wiring the
/// same callbacks (`onLog`/`onReading`/`onUpdate`/`onConnectionState`/`onArchive`)
/// their constructors accept, so the service host, watchdog, controller, chart,
/// stats, alarms and backend queue are all shared.
abstract class CgmConnection {
  /// Find, connect, authenticate, and begin streaming. Safe to call again after
  /// a drop (the watchdog does this).
  Future<void> connect();

  /// Tear down streams + the BLE link.
  Future<void> dispose();

  bool get isConnected;
  bool get isConnecting;

  /// Total session length reported by the sensor (for the expiry warning), or
  /// null when unknown.
  int? get sessionLengthSec;

  /// The latest known glucose value (live, else newest history point).
  int? get latestMgDl;

  /// Trend of the latest live reading in mg/dL per minute (null if none yet).
  double? get latestTrendPerMin;

  /// Per-sensor watchdog cadence (see [CgmTiming]).
  CgmTiming get timing;
}
