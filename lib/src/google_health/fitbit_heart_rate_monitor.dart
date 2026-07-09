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
  static final Guid _fitbitPrivateService =
      Guid('089810cc-ef89-11e9-81b4-2a2ae2dbcce4');

  int? bpm;
  DateTime? lastUpdate;
  FitbitHrStatus status = FitbitHrStatus.idle;
  String message = '';

  bool _running = false;
  bool _foundTarget = false;
  bool _triedCacheClear = false;
  final Set<String> _seen = {};
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  bool get isRunning => _running;

  void _set(FitbitHrStatus next, String text) {
    status = next;
    message = text;
    debugPrint('[fitbit-hr] $text');
    notifyListeners();
  }

  /// Begins scanning + connecting; idempotent. Waits up to 12 s for the BLE
  /// adapter (the G7 pipeline owns the permission/adapter prompts, this only
  /// reads).
  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    _foundTarget = false;
    _triedCacheClear = false;
    if (!await FlutterBluePlus.isSupported) {
      _set(FitbitHrStatus.error, 'Bluetooth not supported.');
      _running = false;
      return;
    }
    if (!await _ensurePermissions()) {
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
    final known = await _knownFitbit();
    if (known != null) {
      debugPrint('[fitbit-hr] using known device ${known.remoteId.str}');
      await _connect(known);
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
      debugPrint('[fitbit-hr] known device ${device.remoteId.str} ("$name")');
      if (name.toLowerCase().contains('fitbit') ||
          RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(name)) {
        return device;
      }
    }
    return null;
  }

  /// Requests scan/connect permission (granted already if a G7 is set up, but the
  /// HR page can run without one — the friend's standalone app relied on a manual
  /// grant). Returns true if both are granted.
  Future<bool> _ensurePermissions() async {
    if (await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted) {
      return true;
    }
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
  }

  /// Broad scan (no service filter — the Air only advertises 0x180D in some
  /// states), picking the first Fitbit by advertised name.
  Future<void> _scanAndConnect() async {
    _seen.clear();
    _set(FitbitHrStatus.scanning, 'Scanning for your Fitbit…');
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      _logScan(results);
      final target = _pickTarget(results);
      if (target != null && !_foundTarget) {
        _foundTarget = true;
        _scanSub?.cancel();
        FlutterBluePlus.stopScan();
        _connect(target.device);
      }
    }, onError: (Object error) => _set(FitbitHrStatus.error, 'Scan error: $error'));
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    // Wait for the scan to actually end (isScanning goes true→false). We must
    // NOT listen before startScan: isScanning re-emits its last value (false) to
    // new subscribers, which would fire "not found" instantly.
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    if (!_foundTarget && _running && status == FitbitHrStatus.scanning) {
      final seen = _seen.isEmpty ? 'no BLE devices' : _seen.join(', ');
      _set(FitbitHrStatus.notFound, 'No Fitbit found. Saw: $seen');
      _running = false;
    }
  }

  void _logScan(List<ScanResult> results) {
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
    _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && _running) {
        _foundTarget = false;
        Future.delayed(const Duration(seconds: 2), () {
          if (_running) {
            _findAndConnect();
          }
        });
      }
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
      _set(FitbitHrStatus.connected, 'Connected — put the band on your wrist.');
    } catch (error) {
      _set(FitbitHrStatus.error, 'Connection failed: $error');
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
    bpm = sample.bpm;
    lastUpdate = DateTime.now();
    _set(FitbitHrStatus.streaming, 'Live heart rate.');
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
    stop();
    super.dispose();
  }
}
