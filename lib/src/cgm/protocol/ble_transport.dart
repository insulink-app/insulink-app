import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'uuids.dart';

/// Thin wrapper over flutter_blue_plus that exposes the three G7 pipes the
/// reader needs: Authentication (handshake), Control (commands/EGV), Backfill
/// (history). Android-first; iOS will need the same characteristics but stricter
/// permission/background handling.
class BleTransport {
  BleTransport(this.device);

  final BluetoothDevice device;

  BluetoothCharacteristic? _auth;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _backfill;
  BluetoothCharacteristic? _jpake;

  final _authRx = StreamController<List<int>>.broadcast();
  final _controlRx = StreamController<List<int>>.broadcast();
  final _backfillRx = StreamController<List<int>>.broadcast();

  Stream<List<int>> get authStream => _authRx.stream;

  Stream<List<int>> get controlStream => _controlRx.stream;

  Stream<List<int>> get backfillStream => _backfillRx.stream;

  // 3538 (J-PAKE/cert) bytes are buffered continuously from connect so callers
  // can take N bytes regardless of when the notifications arrived (the sensor
  // streams payloads faster than a fresh stream listener can attach).
  final List<int> _jpakeBuf = [];
  final List<MapEntry<int, Completer<Uint8List>>> _jpakeWaiters = [];

  final List<StreamSubscription> _subs = [];

  void _onJpakeBytes(List<int> chunk) {
    _jpakeBuf.addAll(chunk);
    while (_jpakeWaiters.isNotEmpty &&
        _jpakeBuf.length >= _jpakeWaiters.first.key) {
      final waiter = _jpakeWaiters.removeAt(0);
      final out = Uint8List.fromList(_jpakeBuf.sublist(0, waiter.key));
      _jpakeBuf.removeRange(0, waiter.key);
      waiter.value.complete(out);
    }
  }

  /// Scan for a G7 sensor. The G7 advertises a device name like `DXCMxx`
  /// (the two trailing chars relate to the pairing identity). Returns the first
  /// match, or null on timeout.
  ///
  /// If [wantedId] is given, ONLY a device with that BLE remoteId matches — used
  /// on reconnect so we never grab a different G7 (a neighbour's, or an old
  /// sensor) that happens to advertise first, which would fail key-confirmation
  /// against our stored key. Without it, the first `DXCM…` device matches.
  ///
  /// [wantedId] is ALSO passed as a native `withRemoteIds` scan filter: Android
  /// delivers no results for an UNfiltered scan while the screen is off, so a
  /// background reconnect would otherwise stall for minutes until the app/screen
  /// is opened. A native address filter makes the scan return results screen-off.
  static Future<BluetoothDevice?> scanForSensor({
    String namePrefix = 'DXCM',
    String? wantedId,
    Duration timeout = const Duration(seconds: 120),
    void Function(String) log = print,
  }) async {
    // Android reports BluetoothAdapterState.unknown in a freshly-spawned isolate
    // (the foreground-service isolate hosting this scan) until the adapter-state
    // stream first emits — and startScan against an `unknown` adapter delivers NO
    // results, which is the multi-hour "0 devices found" stall. Subscribing to
    // adapterState forces a native read; wait for `on` before scanning. If BT is
    // genuinely off this times out and we proceed as before (no regression).
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.adapterState
            .firstWhere((state) => state == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 15));
      } catch (error) {
        log('scan: adapter not on after wait ($error) — scanning anyway');
      }
    }

    final completer = Completer<BluetoothDevice?>();
    late StreamSubscription sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        // Match the ADVERTISED name, not just platformName: on Android the
        // latter is `BluetoothDevice.getName()` — the OS name cache — which is
        // empty for a sensor the phone has never bonded/cached, so a G7 that is
        // advertising as DXCM… right in front of us was silently skipped ("no
        // sensor found" while scanning forever). advName comes from the
        // advertisement itself and is always present for the G7.
        final advertisedName = result.advertisementData.advName;
        final matches = wantedId != null
            ? result.device.remoteId.str == wantedId
            : advertisedName.startsWith(namePrefix) ||
                  result.device.platformName.startsWith(namePrefix);
        if (matches) {
          if (!completer.isCompleted) {
            completer.complete(result.device);
          }
        }
      }
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      // Don't use the FBP default ScanMode.lowLatency: this scan runs nearly
      // continuously (120s windows back-to-back, 24/7) on the reconnect path, and
      // continuous lowLatency scanning WEDGES the BLE controller on Android
      // (esp. Samsung) — the scanner silently returns 0 results until the user
      // toggles Bluetooth off/on. turnOff() is a no-op on Android 13+, so we
      // can't recover programmatically; the only fix is to scan gently. Balanced
      // (~25% radio duty vs lowLatency's 100%) still catches the G7's periodic
      // advertisement via the offloaded withRemoteIds filter below.
      androidScanMode: AndroidScanMode.balanced,
      // Pass the stored remoteId as a NATIVE address filter. This is load-bearing
      // for background reads: Android returns NO results for an unfiltered scan
      // while the screen is off, so without this filter a screen-off reconnect
      // goes blind for the whole screen-off stretch (the multi-hour overnight
      // outage) and only recovers when the screen comes back on. The earlier
      // unfiltered DIAGNOSTIC confirmed the sensor's address does NOT rotate
      // (DXCM… stays at the same remoteId), so the filter is safe to restore.
      withRemoteIds: wantedId != null ? [wantedId] : const [],
    );
    final device = await completer.future
        .timeout(timeout, onTimeout: () => null)
        .whenComplete(() async {
          await sub.cancel();
          await FlutterBluePlus.stopScan();
        });
    return device;
  }

  /// Connect, discover services, and bind the three characteristics. Throws a
  /// [StateError] naming the expected [G7Uuids] if the auth or J-PAKE
  /// characteristic is missing.
  ///
  /// [autoConnect] picks the reconnect strategy (Juggluco's Android-13+ path):
  /// register the device on the BLE controller's allowlist and let the OS
  /// reconnect when the sensor next advertises — NO app-level scanning, so the
  /// native scanner can't wedge (the cause of the "toggle Bluetooth by hand"
  /// outages). Used for every connect once the OS has seen the sensor in this
  /// process — either from the cached device id, or right after the scan that
  /// found it. A direct connect is only left as the theoretical `autoConnect:
  /// false` path: its 35 s timeout expires against the G7's ~1 s advertising
  /// window and fails with 147 GATT_CONNECTION_TIMEOUT.
  Future<void> connectAndBind({
    bool autoConnect = false,
    void Function(String) log = print,
  }) async {
    // FBP 2.x requires a license declaration; use the appropriate value for
    // your distribution (nonprofit/open-source here — see the FBP License enum).
    if (autoConnect) {
      await _armAutoConnect(log);
    } else {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 35),
      );
    }
    log('connected to ${device.platformName} (${device.remoteId})');

    // The G7 keeps the link up only briefly (~1 s) and closes it itself after a
    // delivery, so a slow default connection interval can make the first control
    // write miss the window — surfacing as GATT_ERROR (133) + an immediate drop.
    // Ask for a fast interval so the post-auth writes land inside the window.
    // Android-only and best-effort: never let it abort the handshake.
    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
    } catch (_) {}

    // discoverServices has no internal timeout: if the link wedges right after
    // connect (seen in Doze), an un-bounded await here would pin `_connecting`
    // true forever and silence the watchdog. Bound it so connect() always
    // resolves and the watchdog can retry.
    final services = await device.discoverServices().timeout(
      const Duration(seconds: 30),
    );
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final uuid128 = characteristic.uuid.str128.toLowerCase();
        if (uuid128 == G7Uuids.authentication) {
          _auth = characteristic;
        }
        if (uuid128 == G7Uuids.control) {
          _control = characteristic;
        }
        if (uuid128 == G7Uuids.backfill) {
          _backfill = characteristic;
        }
        if (uuid128 == G7Uuids.jpake) {
          _jpake = characteristic;
        }
      }
    }
    if (_auth == null || _jpake == null) {
      throw StateError(
        'Auth (${G7Uuids.authentication}) or J-PAKE (${G7Uuids.jpake}) '
        'characteristic not found — check the logged UUIDs and update G7Uuids.',
      );
    }

    // The G7 expects the auth handshake to start right after these two
    // subscriptions — do NOT subscribe control/backfill yet, or it disconnects.
    // Juggluco: notify on 3538 (jpake), indicate on 3535 (auth).
    _subs.add(_jpake!.onValueReceived.listen(_onJpakeBytes));
    await _jpake!.setNotifyValue(true);
    log('subscribed to ${_jpake!.uuid} (buffered)');
    await _subscribe(_auth!, _authRx, log, forceIndications: true);
  }

  /// Arm the OS allowlist reconnect and wait for the link to come up. FBP's
  /// `connect(autoConnect:true)` returns IMMEDIATELY (it never waits for the
  /// connection) and forbids an `mtu` argument, so we (1) wait for the
  /// `connected` state ourselves before [connectAndBind] discovers services, and
  /// (2) raise the MTU by hand afterwards — without it EGV/control frames split
  /// across 20-byte notifications and parse to nothing. The wait is bounded to a
  /// single ~5-min G7 delivery cycle (+margin); on timeout it throws so the
  /// caller retries and, after repeated misses, falls back to a scan.
  Future<void> _armAutoConnect(void Function(String) log) async {
    await device.connect(
      license: License.nonprofit,
      autoConnect: true,
      mtu: null,
    );
    if (!device.isConnected) {
      log('autoConnect armed — waiting for ${device.remoteId} to advertise…');
      await device.connectionState
          .firstWhere((state) => state == BluetoothConnectionState.connected)
          .timeout(const Duration(minutes: 6));
    }
    await device.requestMtu(512);
  }

  /// Subscribe to control + backfill AFTER authentication succeeds.
  Future<void> enableDataChannels({void Function(String) log = print}) async {
    if (_control != null) {
      await _subscribe(_control!, _controlRx, log, forceIndications: true);
    }
    if (_backfill != null) {
      await _subscribe(_backfill!, _backfillRx, log);
    }
  }

  Future<void> _subscribe(
    BluetoothCharacteristic characteristic,
    StreamController<List<int>> sink,
    void Function(String) log, {
    bool forceIndications = false,
  }) async {
    final sub = characteristic.onValueReceived.listen(sink.add);
    _subs.add(sub);
    await characteristic.setNotifyValue(
      true,
      forceIndications: forceIndications,
    );
    log(
      'subscribed to ${characteristic.uuid}'
      '${forceIndications ? " (indicate)" : ""}',
    );
  }

  /// Write with a small retry on transient Android GATT faults:
  ///  - 201 / WRITE_REQUEST_BUSY: a prior write hasn't drained yet.
  ///  - 133 / GATT_ERROR on the FIRST write right after connect+subscribe: the
  ///    connection parameters / stack haven't settled yet. This is the classic
  ///    Android "133" flake; a short backoff + retry usually clears it.
  ///
  /// 133 is only retried while the link is actually up — if the sensor has
  /// dropped the connection (the G7 closes its own link after each delivery), the
  /// write fails fast to the caller so the watchdog can reconnect on the next
  /// advertisement, instead of looping here against a dead link.
  Future<void> _write(
    BluetoothCharacteristic characteristic,
    List<int> bytes, {
    required bool withoutResponse,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await characteristic.write(bytes, withoutResponse: withoutResponse);
        return;
      } catch (e) {
        final message = e.toString().toUpperCase();
        final busy =
            message.contains('201') || message.contains('WRITE_REQUEST_BUSY');
        final gattFlake =
            (message.contains('133') || message.contains('GATT_ERROR')) &&
            device.isConnected;
        if (!(busy || gattFlake) || attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: gattFlake ? 150 : 60),
        );
      }
    }
  }

  /// Write a framed message (opcode byte + payload) to the Authentication
  /// characteristic. G7 auth writes are write-with-response.
  Future<void> writeAuth(List<int> bytes) =>
      _write(_auth!, bytes, withoutResponse: false);

  Future<void> writeControl(List<int> bytes) =>
      _write(_control!, bytes, withoutResponse: false);

  /// Request backfill (history) over [startSec]..[endSec] seconds-since-session-
  /// start. Command is `0x59 ‖ int32 start ‖ int32 end` (LE) on the control
  /// characteristic; records stream back on the backfill characteristic.
  Future<void> requestBackfill(int startSec, int endSec) async {
    final frame = ByteData(9);
    frame.setUint8(0, 0x59);
    frame.setInt32(1, startSec, Endian.little);
    frame.setInt32(5, endSec, Endian.little);
    await writeControl(frame.buffer.asUint8List());
  }

  /// Trigger Android BLE bonding (the final pairing step the G7 expects).
  Future<void> createBond() async {
    try {
      // Some stacks never resolve createBond (bond dialog dismissed / silent
      // OS bond); bound it so it can't hang the handshake indefinitely.
      await device.createBond().timeout(const Duration(seconds: 30));
    } catch (e) {
      // Some stacks bond implicitly; surface but don't abort.
    }
  }

  /// Write a large J-PAKE/cert payload to the 3538 characteristic in hard
  /// 20-byte chunks, WRITE_NO_RESPONSE (matches Juggluco's sendcertthread).
  Future<void> writeJpake(List<int> bytes) async {
    for (var offset = 0; offset < bytes.length; offset += 20) {
      final end = (offset + 20 < bytes.length) ? offset + 20 : bytes.length;
      await _write(_jpake!, bytes.sublist(offset, end), withoutResponse: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  /// Drop any buffered 3538 bytes and pending waiters. Call before (re)starting a
  /// handshake so leftover/misaligned data from a previous attempt can't shift
  /// the byte alignment of the round payloads (which would corrupt J-PAKE).
  void clearJpakeBuffer() {
    _jpakeBuf.clear();
    for (final waiter in _jpakeWaiters) {
      if (!waiter.value.isCompleted) {
        waiter.value.completeError(StateError('jpake buffer cleared'));
      }
    }
    _jpakeWaiters.clear();
  }

  /// Take [total] bytes from the continuously-buffered 3538 stream (e.g. 160 for
  /// a round payload, or the cert size). Completes as soon as enough bytes have
  /// accumulated, even if they arrived before this call.
  Future<Uint8List> takeJpake(
    int total, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final completer = Completer<Uint8List>();
    _jpakeWaiters.add(MapEntry(total, completer));
    _onJpakeBytes(const []); // service immediately if already buffered
    return completer.future.timeout(timeout);
  }

  Future<void> dispose() async {
    for (final subscription in _subs) {
      await subscription.cancel();
    }
    await _authRx.close();
    await _controlRx.close();
    await _backfillRx.close();
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
