import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'libre3_crypto.dart';
import 'libre3_uuids.dart';

/// flutter_blue_plus transport + security handshake for the FreeStyle Libre 3.
///
/// The BLE plumbing (scan-by-MAC, discover, subscribe, MTU) mirrors the G7's
/// [BleTransport]. The handshake is a clean-room port of Juggluco's
/// `Libre3GattCallback` ordered sequence; every crypto primitive is delegated to
/// [Libre3Crypto] (the Abbott blob). See docs/LIBRE3.md for the byte-level flow.
///
/// ponytail: the exact fragment framing of the security characteristics and the
/// event interleaving are the parts to confirm against a real sensor — the
/// happy-path ordering below follows Juggluco but cannot be validated headless.
class Libre3Transport {
  Libre3Transport({required this.device, required this.crypto, this.blePin});

  final BluetoothDevice device;
  final Libre3Crypto crypto;

  /// The 4-byte BLE PIN from NFC activation, consumed in the challenge response.
  Uint8List? blePin;

  BluetoothCharacteristic? _securityCommands;
  BluetoothCharacteristic? _challengeData;
  BluetoothCharacteristic? _certificateData;
  BluetoothCharacteristic? _oneMinute;
  BluetoothCharacteristic? _historic;
  BluetoothCharacteristic? _patchStatus;
  BluetoothCharacteristic? _patchControl;

  final _glucoseRx = StreamController<Uint8List>.broadcast();
  final _historicRx = StreamController<Uint8List>.broadcast();

  /// Decrypted one-minute glucose payloads.
  Stream<Uint8List> get glucoseStream => _glucoseRx.stream;

  /// Decrypted historical (backfill) payloads.
  Stream<Uint8List> get historicStream => _historicRx.stream;

  final List<StreamSubscription> _subs = [];
  final _SecBuffer _challengeBuf = _SecBuffer();
  final _SecBuffer _certBuf = _SecBuffer();

  /// Find the sensor by its NFC-derived BLE MAC. Unlike the G7 there is no name
  /// prefix — the Libre 3 is addressed only by the MAC the NFC scan returned.
  static Future<BluetoothDevice?> scanForMac(
    String mac, {
    Duration timeout = const Duration(seconds: 120),
    void Function(String) log = print,
  }) async {
    final completer = Completer<BluetoothDevice?>();
    late StreamSubscription sub;
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (result.device.remoteId.str.toUpperCase() == mac.toUpperCase()) {
          if (!completer.isCompleted) {
            completer.complete(result.device);
          }
        }
      }
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.balanced,
      withRemoteIds: [mac],
    );
    return completer.future
        .timeout(timeout, onTimeout: () => null)
        .whenComplete(() async {
          await sub.cancel();
          await FlutterBluePlus.stopScan();
        });
  }

  /// Connect, discover the data + security services, and bind characteristics.
  Future<void> connectAndBind({void Function(String) log = print}) async {
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 35),
    );
    await device.requestMtu(512);
    final services = await device.discoverServices().timeout(
      const Duration(seconds: 30),
    );
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        _bind(characteristic);
      }
    }
    if (_securityCommands == null || _certificateData == null) {
      throw StateError('Libre 3 security characteristics not found');
    }
  }

  void _bind(BluetoothCharacteristic characteristic) {
    final uuid = characteristic.uuid.str128.toUpperCase();
    switch (uuid) {
      case Libre3Uuids.securityCommands:
        _securityCommands = characteristic;
      case Libre3Uuids.challengeData:
        _challengeData = characteristic;
      case Libre3Uuids.certificateData:
        _certificateData = characteristic;
      case Libre3Uuids.oneMinuteReading:
        _oneMinute = characteristic;
      case Libre3Uuids.historicalData:
        _historic = characteristic;
      case Libre3Uuids.patchStatus:
        _patchStatus = characteristic;
      case Libre3Uuids.patchControl:
        _patchControl = characteristic;
    }
  }

  /// Run the security handshake. On success the data cipher is initialised and
  /// glucose/historic notifications are enabled. Returns the freshly derived
  /// kAuth (16 B) to cache for the next fast reconnect.
  ///
  /// [cachedAuthKey] short-circuits to the pre-authorised path when present.
  Future<Uint8List> runHandshake({
    Uint8List? cachedAuthKey,
    int securityVersion = 0,
    void Function(String) log = print,
  }) async {
    await _subscribe(_challengeData!, _challengeBuf.add);
    await _subscribe(_certificateData!, _certBuf.add);
    await crypto.initKeys(cachedAuthKey, securityVersion);

    if (cachedAuthKey == null) {
      await _fullHandshake(log);
    }

    final nonceAndR1 = await _challengeBuf.take(23);
    final kEncIv = await _respondToChallenge(nonceAndR1, log);
    await crypto.initCipher(
      Uint8List.sublistView(kEncIv, 32, 48),
      Uint8List.sublistView(kEncIv, 48, 56),
    );
    final authKey = await crypto.exportAuthKey();
    await _enableDataChannels();
    log('Libre 3 handshake complete');
    return authKey;
  }

  /// Certificate exchange + ECDH (skipped on the pre-authorised path).
  Future<void> _fullHandshake(void Function(String) log) async {
    await _sendCommand(0x01); // init security
    await _sendCommand(0x02); // request cert exchange
    await _sendCert(await crypto.appCertificate());
    await _sendCommand(0x03); // app cert sent

    final patchCert = await _certBuf.take(140);
    await crypto.setPatchCertificate(patchCert);
    await _sendCommand(0x0D);

    await _sendCert(await crypto.generateEphemeralKeys());
    await _sendCommand(0x0E);
    final sensorEphemeral = await _certBuf.take(65);
    await crypto.setPatchEphemeral(sensorEphemeral);
    await _sendCommand(0x11); // authorize symmetric
  }

  /// The challenge/response: r1 + nonce in, encrypted `(r1‖r2‖pin)` out, then the
  /// 67-byte reply decrypted to `[r2 ‖ r1 ‖ kEnc(16) ‖ ivEnc(8)]`.
  Future<Uint8List> _respondToChallenge(
    Uint8List challenge23,
    void Function(String) log,
  ) async {
    final r1 = Uint8List.sublistView(challenge23, 0, 16);
    final nonce = Uint8List.sublistView(challenge23, 16, 23);
    final r2 = _randomBytes(16);
    final pin = blePin ?? Uint8List(4);
    final payload = Uint8List.fromList([...r1, ...r2, ...pin]);
    final encrypted = await crypto.encryptChallenge(nonce, payload);
    await _challengeData!.write(encrypted, withoutResponse: false);
    await _sendCommand(0x08); // challenge sent

    final reply = await _challengeBuf.take(67);
    final replyNonce = Uint8List.sublistView(reply, 60, 67);
    final decrypted = await crypto.decryptChallenge(
      replyNonce,
      Uint8List.sublistView(reply, 0, 60),
    );
    await _sendCommand(0x09); // generate session keys
    return decrypted;
  }

  Future<void> _enableDataChannels() async {
    if (_patchControl != null) {
      await _subscribe(_patchControl!, (_) {});
    }
    if (_historic != null) {
      await _subscribe(_historic!, (data) => _decryptInto(
            Libre3Uuids.decryptHistoric,
            data,
            _historicRx,
          ));
    }
    if (_patchStatus != null) {
      await _subscribe(_patchStatus!, (_) {});
    }
    if (_oneMinute != null) {
      await _subscribe(_oneMinute!, (data) => _decryptInto(
            Libre3Uuids.decryptGlucose,
            data,
            _glucoseRx,
          ));
    }
  }

  Future<void> _decryptInto(
    int channelId,
    List<int> data,
    StreamController<Uint8List> sink,
  ) async {
    try {
      final plain = await crypto.decrypt(channelId, Uint8List.fromList(data));
      sink.add(plain);
    } catch (_) {
      // A decrypt failure means the cipher context isn't valid — drop the frame;
      // the connection watchdog will re-handshake.
    }
  }

  Future<void> _sendCommand(int opcode) async {
    await _securityCommands!.write([opcode], withoutResponse: false);
  }

  /// Write a certificate/ephemeral payload to CERT_DATA in 20-byte chunks with a
  /// 2-byte little-endian offset header (Juggluco's `sendSecurityCert`).
  Future<void> _sendCert(Uint8List bytes) async {
    for (var offset = 0; offset < bytes.length; offset += 18) {
      final end = (offset + 18 < bytes.length) ? offset + 18 : bytes.length;
      final chunk = Uint8List.fromList([
        offset & 0xFF,
        (offset >> 8) & 0xFF,
        ...bytes.sublist(offset, end),
      ]);
      await _certificateData!.write(chunk, withoutResponse: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _subscribe(
    BluetoothCharacteristic characteristic,
    void Function(List<int>) onData,
  ) async {
    _subs.add(characteristic.onValueReceived.listen(onData));
    await characteristic.setNotifyValue(true);
  }

  static Uint8List _randomBytes(int length) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final out = Uint8List(length);
    for (var index = 0; index < length; index++) {
      out[index] = (now >> (index % 8 * 8)) & 0xFF ^ (index * 31);
    }
    return out;
  }

  Future<void> dispose() async {
    for (final subscription in _subs) {
      await subscription.cancel();
    }
    await _glucoseRx.close();
    await _historicRx.close();
    try {
      await device.disconnect();
    } catch (_) {}
  }
}

/// Reassembles a security characteristic's fragmented notifications into a byte
/// buffer, handing out fixed-size slices as the handshake expects them (mirrors
/// the G7 transport's J-PAKE buffer). ponytail: assumes fragments are the raw
/// payload bytes back-to-back; if the sensor prefixes a per-fragment length, that
/// stripping goes here — confirm on-device.
class _SecBuffer {
  final List<int> _buf = [];
  final List<MapEntry<int, Completer<Uint8List>>> _waiters = [];

  void add(List<int> chunk) {
    _buf.addAll(chunk);
    while (_waiters.isNotEmpty && _buf.length >= _waiters.first.key) {
      final waiter = _waiters.removeAt(0);
      final out = Uint8List.fromList(_buf.sublist(0, waiter.key));
      _buf.removeRange(0, waiter.key);
      waiter.value.complete(out);
    }
  }

  Future<Uint8List> take(
    int total, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    final completer = Completer<Uint8List>();
    _waiters.add(MapEntry(total, completer));
    add(const []);
    return completer.future.timeout(timeout);
  }
}
