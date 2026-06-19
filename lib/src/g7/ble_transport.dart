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
      final w = _jpakeWaiters.removeAt(0);
      final out = Uint8List.fromList(_jpakeBuf.sublist(0, w.key));
      _jpakeBuf.removeRange(0, w.key);
      w.value.complete(out);
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
    Duration timeout = const Duration(seconds: 600),
  }) async {
    final completer = Completer<BluetoothDevice?>();
    late StreamSubscription sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final matches = wantedId != null
            ? r.device.remoteId.str == wantedId
            : r.device.platformName.startsWith(namePrefix);
        if (matches) {
          if (!completer.isCompleted) completer.complete(r.device);
        }
      }
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
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

  /// Connect, discover services, and bind the three characteristics. Logs every
  /// service/characteristic so you can CONFIRM the UUIDs in [G7Uuids] against
  /// your sensor (run this once and compare).
  Future<void> connectAndBind({void Function(String) log = print}) async {
    // FBP 2.x requires a license declaration; use the appropriate value for
    // your distribution (nonprofit/open-source here — see the FBP License enum).
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 300),
    );
    log('connected to ${device.platformName} (${device.remoteId})');

    final services = await device.discoverServices();
    for (final s in services) {
      log('service ${s.uuid}');
      for (final c in s.characteristics) {
        log('  char ${c.uuid}  props=${_props(c)}');
        final u = c.uuid.str128.toLowerCase();
        if (u == G7Uuids.authentication) _auth = c;
        if (u == G7Uuids.control) _control = c;
        if (u == G7Uuids.backfill) _backfill = c;
        if (u == G7Uuids.jpake) _jpake = c;
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

  /// Subscribe to control + backfill AFTER authentication succeeds.
  Future<void> enableDataChannels({void Function(String) log = print}) async {
    if (_control != null) {
      await _subscribe(_control!, _controlRx, log, forceIndications: true);
    }
    if (_backfill != null) await _subscribe(_backfill!, _backfillRx, log);
  }

  Future<void> _subscribe(
    BluetoothCharacteristic c,
    StreamController<List<int>> sink,
    void Function(String) log, {
    bool forceIndications = false,
  }) async {
    final sub = c.onValueReceived.listen(sink.add);
    _subs.add(sub);
    await c.setNotifyValue(true, forceIndications: forceIndications);
    log('subscribed to ${c.uuid}${forceIndications ? " (indicate)" : ""}');
  }

  /// Write with a small retry on the transient Android GATT "write request
  /// busy" (201) error, which happens when a prior write hasn't drained yet.
  Future<void> _write(
    BluetoothCharacteristic c,
    List<int> bytes, {
    required bool withoutResponse,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await c.write(bytes, withoutResponse: withoutResponse);
        return;
      } catch (e) {
        final busy =
            e.toString().contains('201') ||
            e.toString().toUpperCase().contains('WRITE_REQUEST_BUSY');
        if (!busy || attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 60));
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
    final b = ByteData(9);
    b.setUint8(0, 0x59);
    b.setInt32(1, startSec, Endian.little);
    b.setInt32(5, endSec, Endian.little);
    await writeControl(b.buffer.asUint8List());
  }

  /// Trigger Android BLE bonding (the final pairing step the G7 expects).
  Future<void> createBond() async {
    try {
      await device.createBond();
    } catch (e) {
      // Some stacks bond implicitly; surface but don't abort.
    }
  }

  /// Write a large J-PAKE/cert payload to the 3538 characteristic in hard
  /// 20-byte chunks, WRITE_NO_RESPONSE (matches Juggluco's sendcertthread).
  Future<void> writeJpake(List<int> bytes) async {
    for (var i = 0; i < bytes.length; i += 20) {
      final end = (i + 20 < bytes.length) ? i + 20 : bytes.length;
      await _write(_jpake!, bytes.sublist(i, end), withoutResponse: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  /// Drop any buffered 3538 bytes and pending waiters. Call before (re)starting a
  /// handshake so leftover/misaligned data from a previous attempt can't shift
  /// the byte alignment of the round payloads (which would corrupt J-PAKE).
  void clearJpakeBuffer() {
    _jpakeBuf.clear();
    for (final w in _jpakeWaiters) {
      if (!w.value.isCompleted) {
        w.value.completeError(StateError('jpake buffer cleared'));
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
    final c = Completer<Uint8List>();
    _jpakeWaiters.add(MapEntry(total, c));
    _onJpakeBytes(const []); // service immediately if already buffered
    return c.future.timeout(timeout);
  }

  String _props(BluetoothCharacteristic c) {
    final p = c.properties;
    return [
      if (p.read) 'read',
      if (p.write) 'write',
      if (p.writeWithoutResponse) 'writeNR',
      if (p.notify) 'notify',
      if (p.indicate) 'indicate',
    ].join(',');
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _authRx.close();
    await _controlRx.close();
    await _backfillRx.close();
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
