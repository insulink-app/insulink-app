import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'heart_rate_measurement.dart';

/// Where the live-BLE reader is in its scan → connect → stream flow. Surfaced in
/// the HeartRatePage banner so a missing pulse is diagnosable (the Fitbit often
/// only exposes 0x180D after "Share Heart Rate" is enabled in Google Health).
enum FitbitHrStatus {
  idle,
  bluetoothOff,
  scanning,
  notFound,
  connecting,
  connected,
  streaming,
  error,
}

/// Live BLE heart-rate reader for a Fitbit Air (or any SIG Heart Rate device).
/// Scans → connects → subscribes to 0x2A37 → parses → notifies at ~1 Hz. Runs in
/// the UI isolate only while a page wants live pulse (start/stop with the page):
/// the background history path stays on Health Connect (see cgm_service
/// `_maybePollHeartRate`). Contributed as a test integration by a Fitbit-BLE
/// side project.
class FitbitHeartRateMonitor extends ChangeNotifier {
  /// Standard Bluetooth SIG UUIDs the Fitbit Air exposes in the clear once worn.
  static final Guid _heartRateService = Guid('180D');
  static final Guid _heartRateMeasurement = Guid('2A37');

  /// Fitbit's private GATT service. A band bonded to this phone (paired via
  /// Google Health) advertises ONLY this — not 0x180D — and names itself by its
  /// MAC in hex (e.g. "F46ED6389733"), so it matches neither the name nor the
  /// 0x180D checks.
  static final Guid _fitbitPrivateService = Guid(
    '089810cc-ef89-11e9-81b4-2a2ae2dbcce4',
  );

  int? bpm;
  DateTime? lastUpdate;
  FitbitHrStatus status = FitbitHrStatus.idle;
  String message = '';

  /// Rolling buffer of live BLE samples (one per ~15 s, last 24 h) so the
  /// intraday chart can extend past Health Connect's last sync — the Fitbit app
  /// syncs to Health Connect hours behind the band, so the curve otherwise stops
  /// well before the live pulse the banner shows.
  final List<({DateTime at, int bpm})> liveHistory = [];

  bool _running = false;
  bool _knownOnly = false;
  bool _foundTarget = false;

  /// When the last broad scan ended finding no band. A broad (unfiltered) scan is
  /// the most power-hungry BLE operation, and [start] runs on every app resume;
  /// within this cooldown we skip re-broad-scanning (the cheap known-device
  /// connect still runs), so app-switching doesn't fire a 20 s scan each time.
  DateTime? _lastEmptyScanAt;
  static const _emptyScanCooldown = Duration(minutes: 3);
  bool _triedCacheClear = false;
  final Set<String> _seen = {};
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  bool get isRunning => _running;

  /// Set once [dispose] ran. An in-flight `start`/`_findAndConnect` outlives the
  /// widget tree, so its continuation would call [notifyListeners] on a disposed
  /// notifier — that throw aborted the async chain mid-connect and left an
  /// orphaned GATT client retrying forever (the connect/timeout/133 churn that
  /// starves the G7's scan).
  bool _disposed = false;

  /// `connectionState` REPLAYS the current state on subscribe, so every fresh
  /// [_connect] instantly saw `disconnected` and armed the 2 s retry — which
  /// launched another [_connect] while the first 20 s connect was still pending,
  /// each one arming yet another retry. That is the runaway
  /// connect / "already connecting" / getBondedDevices storm in the logs, and it
  /// starves the G7's own scan. So only a drop that FOLLOWS a real connection
  /// re-arms ([_wasConnected]), and only one attempt runs at a time
  /// ([_attempting]).
  bool _attempting = false;
  bool _wasConnected = false;

  /// When [start] last began an attempt. Every failure path below stands the
  /// monitor down (`_running = false`) and relies on a caller re-running [start]
  /// — the service watchdog does, on every tick. Without this cooldown that
  /// would mean a fresh 20 s connect attempt every tick while the band is simply
  /// out of range or held by Google Health; without the re-runs the FIRST failed
  /// attempt killed live pulse until the app was restarted.
  DateTime? _lastAttemptAt;
  static const _retryCooldown = Duration(seconds: 60);

  void _set(FitbitHrStatus next, String text) {
    status = next;
    message = text;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Begins scanning + connecting; idempotent. Waits up to 12 s for the BLE
  /// adapter (the G7 pipeline owns the permission/adapter prompts, this only
  /// reads).
  ///
  /// [knownOnly] connects ONLY to an already-bonded/known band and never scans —
  /// used in the foreground-service isolate, where a broad scan would fight the
  /// G7's own BLE scanner (see the app CLAUDE.md scanner-wedge notes) and where
  /// the band is bonded anyway once it has been used once in the foreground.
  ///
  /// Safe to call repeatedly: a running monitor no-ops, and a stood-down one
  /// retries at most once per [_retryCooldown].
  Future<void> start({bool knownOnly = false}) async {
    if (_running) {
      return;
    }
    final lastAttempt = _lastAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < _retryCooldown) {
      return;
    }
    _lastAttemptAt = DateTime.now();
    _running = true;
    _knownOnly = knownOnly;
    _foundTarget = false;
    _triedCacheClear = false;
    if (!await FlutterBluePlus.isSupported) {
      _set(FitbitHrStatus.error, 'Bluetooth not supported.');
      _running = false;
      return;
    }
    if (!await _permissionsGranted()) {
      _set(FitbitHrStatus.error, 'Bluetooth permission denied.');
      _running = false;
      return;
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _set(FitbitHrStatus.bluetoothOff, 'Waiting for Bluetooth…');
      try {
        await FlutterBluePlus.adapterState
            .where((state) => state == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        _set(FitbitHrStatus.bluetoothOff, 'Bluetooth is off.');
        _running = false;
        return;
      }
    }
    try {
      await _findAndConnect();
    } catch (error) {
      _set(FitbitHrStatus.error, 'Scan failed: $error');
      _running = false;
    }
  }

  /// The band is bonded to this phone and held in a live connection by Google
  /// Health, so it does NOT advertise (a connected BLE peripheral stops
  /// advertising) — scanning finds nothing. So try the OS's already-known
  /// devices FIRST, connecting directly by id, and only scan as a fallback.
  Future<void> _findAndConnect() async {
    if (_attempting) {
      return;
    }
    _attempting = true;
    try {
      await _findAndConnectOnce();
    } finally {
      _attempting = false;
    }
  }

  /// One attempt: known device first, broad scan as the fallback.
  Future<void> _findAndConnectOnce() async {
    final known = await _knownFitbit();
    if (known != null) {
      await _connect(known);
      return;
    }
    if (_knownOnly) {
      // No bonded band and scanning is disallowed here: go idle and wait for the
      // next attempt (a disconnect re-arm, or the foreground isolate taking over).
      _set(FitbitHrStatus.idle, 'No paired band.');
      _running = false;
      return;
    }
    final lastEmpty = _lastEmptyScanAt;
    if (lastEmpty != null &&
        DateTime.now().difference(lastEmpty) < _emptyScanCooldown) {
      // A recent broad scan already found nothing; don't burn the radio again on
      // this resume. The next scan runs once the cooldown lapses.
      _set(FitbitHrStatus.idle, 'No paired band.');
      _running = false;
      return;
    }
    await _scanAndConnect();
  }

  /// A Fitbit among the OS's bonded or currently-connected devices, or null. The
  /// Air names itself by its MAC in hex, so we accept a "fitbit" name OR a bare
  /// 12-hex-char name (won't match headphones etc.).
  Future<BluetoothDevice?> _knownFitbit() async {
    final candidates = <BluetoothDevice>[
      ...await FlutterBluePlus.bondedDevices,
      ...await FlutterBluePlus.systemDevices(const []),
    ];
    for (final device in candidates) {
      final name = device.platformName;
      if (name.toLowerCase().contains('fitbit') ||
          RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(name)) {
        return device;
      }
    }
    return null;
  }

  /// Whether scan/connect are held. Checks only, never requests: this monitor
  /// starts app-wide from [GoogleHealthState.init], so a request here fires a
  /// bare "allow nearby devices" dialog on launch, ahead of the explained
  /// Bluetooth page in [PermissionOnboarding]. That page (and the G7 start path)
  /// own the prompt; without the grant the live pulse simply stays off.
  Future<bool> _permissionsGranted() async {
    return await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted;
  }

  /// Broad scan (no service filter — the Air only advertises 0x180D in some
  /// states), picking the first Fitbit by advertised name.
  Future<void> _scanAndConnect() async {
    _seen.clear();
    _set(FitbitHrStatus.scanning, 'Scanning for your Fitbit…');
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        _logScan(results);
        final target = _pickTarget(results);
        if (target != null && !_foundTarget) {
          _foundTarget = true;
          _scanSub?.cancel();
          FlutterBluePlus.stopScan();
          _connect(target.device);
        }
      },
      onError: (Object error) =>
          _set(FitbitHrStatus.error, 'Scan error: $error'),
    );
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    // Wait for the scan to actually end (isScanning goes true→false). We must
    // NOT listen before startScan: isScanning re-emits its last value (false) to
    // new subscribers, which would fire "not found" instantly.
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    if (!_foundTarget && _running && status == FitbitHrStatus.scanning) {
      _lastEmptyScanAt = DateTime.now();
      final seen = _seen.isEmpty ? 'no BLE devices' : _seen.join(', ');
      _set(FitbitHrStatus.notFound, 'No Fitbit found. Saw: $seen');
      _running = false;
    }
  }

  void _logScan(List<ScanResult> results) {
    if (!kDebugMode) {
      return;
    }
    for (final result in results) {
      final name = result.advertisementData.advName;
      final label = name.isEmpty
          ? '<no name> ${result.device.remoteId.str}'
          : name;
      if (_seen.add(label)) {
        final services = result.advertisementData.serviceUuids
            .map((uuid) => uuid.str)
            .join(',');
        debugPrint('[fitbit-hr] scan saw $label services=[$services]');
      }
    }
  }

  /// The Fitbit by advertised name, else a device advertising 0x180D or the
  /// Fitbit private service. We do NOT match a bare "air" substring — that hits
  /// AirPods and the like.
  ScanResult? _pickTarget(List<ScanResult> results) {
    for (final result in results) {
      if (result.advertisementData.advName.toLowerCase().contains('fitbit')) {
        return result;
      }
    }
    for (final result in results) {
      final advertised = result.advertisementData.serviceUuids;
      if (advertised.any((uuid) => _matches(uuid, _heartRateService)) ||
          advertised.any((uuid) => _matches(uuid, _fitbitPrivateService))) {
        return result;
      }
    }
    return null;
  }

  Future<void> _connect(BluetoothDevice device) async {
    _device = device;
    _set(FitbitHrStatus.connecting, 'Connecting…');
    await _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _wasConnected = true;
        return;
      }
      if (!_running || !_wasConnected) {
        return;
      }
      _wasConnected = false;
      _foundTarget = false;
      Future.delayed(const Duration(seconds: 2), () {
        if (_running) {
          _findAndConnect();
        }
      });
    });
    try {
      // flutter_blue_plus 2.x requires a License arg; nonprofit = research use.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 20),
      );
      final characteristic = await _findMeasurement(device);
      if (characteristic == null) {
        _set(
          FitbitHrStatus.error,
          'Connected, but 0x180D is off. Enable "Share Heart Rate" in Google '
          'Health, or run on a phone not paired to the band.',
        );
        return;
      }
      await characteristic.setNotifyValue(true);
      _valueSub = characteristic.onValueReceived.listen(_onValue);
      device.cancelWhenDisconnected(_valueSub!);
      _lastEmptyScanAt = null;
      _set(FitbitHrStatus.connected, 'Connected — put the band on your wrist.');
    } catch (error) {
      // Stand down instead of hammering: an unreachable band (out of range, or
      // held by Google Health — status 133 / connect timeout) is not fixed by
      // retrying seconds later. The service watchdog re-runs `start()` every
      // tick and the cooldown there spaces the retries — standing down without
      // that re-run is what left live pulse dead after one bad attempt.
      _set(FitbitHrStatus.error, 'Connection failed: $error');
      _running = false;
    }
  }

  /// Locates the 0x2A37 characteristic, retrying once after clearing the Android
  /// GATT cache — a bonded phone may have cached a service list without 0x180D.
  Future<BluetoothCharacteristic?> _findMeasurement(
    BluetoothDevice device,
  ) async {
    var services = await device.discoverServices();
    var found = _measurementIn(services);
    if (found == null &&
        defaultTargetPlatform == TargetPlatform.android &&
        !_triedCacheClear) {
      _triedCacheClear = true;
      try {
        await device.clearGattCache();
        await Future.delayed(const Duration(milliseconds: 600));
        services = await device.discoverServices();
        found = _measurementIn(services);
      } catch (error) {
        debugPrint('[fitbit-hr] clearGattCache failed: $error');
      }
    }
    return found;
  }

  BluetoothCharacteristic? _measurementIn(List<BluetoothService> services) {
    for (final service in services) {
      if (!_matches(service.uuid, _heartRateService)) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (_matches(characteristic.uuid, _heartRateMeasurement)) {
          return characteristic;
        }
      }
    }
    return null;
  }

  void _onValue(List<int> value) {
    final sample = HeartRateMeasurement.parse(value);
    if (sample == null) {
      return;
    }
    final now = DateTime.now();
    bpm = sample.bpm;
    lastUpdate = now;
    _recordLive(sample.bpm, now);
    _set(FitbitHrStatus.streaming, 'Live heart rate.');
  }

  /// Appends to [liveHistory], thinned to one point per 15 s and pruned to the
  /// last 24 h (matching the intraday chart's window and resolution).
  void _recordLive(int bpm, DateTime now) {
    final last = liveHistory.isEmpty ? null : liveHistory.last.at;
    if (last != null && now.difference(last).inSeconds < 15) {
      return;
    }
    liveHistory.add((at: now, bpm: bpm));
    while (liveHistory.isNotEmpty &&
        now.difference(liveHistory.first.at) > const Duration(hours: 24)) {
      liveHistory.removeAt(0);
    }
  }

  /// Tolerant Guid compare: flutter_blue_plus may report the 16-bit or the full
  /// 128-bit form, so match if either string contains the other.
  bool _matches(Guid a, Guid b) {
    final sa = a.toString().toLowerCase();
    final sb = b.toString().toLowerCase();
    return sa == sb || sa.contains(sb) || sb.contains(sa);
  }

  Future<void> stop() async {
    _running = false;
    _foundTarget = false;
    _wasConnected = false;
    _lastAttemptAt = null;
    await _scanSub?.cancel();
    await _valueSub?.cancel();
    await _connSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    status = FitbitHrStatus.idle;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
