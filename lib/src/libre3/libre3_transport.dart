import 'dart:async';
import 'dart:math';
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

  // --- security handshake state (Juggluco's Libre3GattCallback) -------------
  // Command phase, advanced by COMMAND_RESPONSE write-completions.
  int _commandPhase = 1;
  // Reassembly of a cert/challenge transfer whose length COMMAND_RESPONSE
  // announced via preparedata; fragments carry an incrementing sequence byte.
  int _rdtLength = 0;
  Uint8List _rdtData = Uint8List(0);
  int _rdtBytes = 0;
  int _rdtSequence = -1;
  // Challenge nonce material.
  final Uint8List _r1 = Uint8List(16);
  final Uint8List _r2 = Uint8List(16);
  final Uint8List _nonce1 = Uint8List(7);
  final Random _random = Random.secure();
  Completer<Uint8List>? _handshake;
  void Function(String) _log = print;

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

  /// Run the security handshake. It is an event-driven state machine (a clean-room
  /// port of Juggluco's `Libre3GattCallback`): commands are written to
  /// COMMAND_RESPONSE and each write-completion advances [_commandPhase]; the
  /// sensor announces each cert/challenge transfer via a COMMAND_RESPONSE
  /// notification ([_preparedata]) and streams it as sequence-numbered fragments
  /// ([_getsecdata]). Completes with the derived kAuth (16 B) to cache for the
  /// next fast reconnect. [cachedAuthKey] takes the pre-authorised path (skip the
  /// cert exchange); [securityVersion] picks the embedded cert/key pair (Juggluco
  /// hardcodes 1 — version 0's cert is rejected).
  Future<Uint8List> runHandshake({
    Uint8List? cachedAuthKey,
    int securityVersion = 1,
    void Function(String) log = print,
  }) async {
    _log = log;
    _handshake = Completer<Uint8List>();
    await _subscribe(_securityCommands!, _onCommandResponse);
    await _subscribe(_certificateData!, (value) => _onSecData(value, _receivedCert));
    await _subscribe(_challengeData!, (value) => _onSecData(value, _receivedChallenge));
    await crypto.initKeys(cachedAuthKey, securityVersion);

    if (cachedAuthKey != null) {
      _commandPhase = 5;
      _drive(() => _writeCommand(0x11)); // pre-authorised: straight to challenge
    } else {
      _commandPhase = 1;
      _drive(() => _writeCommand(0x01)); // init security
    }

    final authKey = await _handshake!.future.timeout(
      const Duration(seconds: 40),
    );
    await _enableDataChannels();
    log('Libre 3 handshake complete');
    return authKey;
  }

  /// A COMMAND_RESPONSE notification: either a 1-byte signal (4 = certificate
  /// accepted → generate session keys) or a `[sig, len]` announcement of an
  /// incoming cert/challenge transfer (Juggluco's `preparedata`).
  void _onCommandResponse(List<int> value) {
    if (value.isEmpty) {
      return;
    }
    final sig = value[0];
    if (value.length == 1) {
      if (sig == 4) {
        _drive(() => _writeCommand(0x09));
      } else {
        _fail('preparedata unexpected signal $sig');
      }
      return;
    }
    final length = value[1];
    if (sig != 8 && sig != 10 && sig != 15) {
      _fail('preparedata unknown signal $sig');
      return;
    }
    _rdtLength = length;
    _rdtData = Uint8List(length);
    _rdtBytes = 0;
    _rdtSequence = -1;
  }

  /// A CERT_DATA / CHALLENGE_DATA fragment: `[sequence, ...data]`. Reassembles
  /// into [_rdtData]; when the announced length is complete, runs [onComplete]
  /// (Juggluco's `getsecdata`).
  void _onSecData(List<int> value, Future<void> Function() onComplete) {
    if (value.isEmpty) {
      return;
    }
    final sequence = value[0];
    if (sequence != _rdtSequence + 1) {
      _fail('sec data out of sequence: $sequence != ${_rdtSequence + 1}');
      return;
    }
    final length = value.length - 1;
    _rdtData.setRange(_rdtBytes, _rdtBytes + length, value, 1);
    _rdtBytes += length;
    _rdtSequence = sequence;
    if (_rdtBytes >= _rdtLength) {
      _drive(onComplete);
    }
  }

  /// A fully reassembled cert transfer: 140 B = sensor patch cert, 65 B = sensor
  /// ephemeral public key.
  Future<void> _receivedCert() async {
    if (_rdtLength == 140) {
      await crypto.setPatchCertificate(_rdtData);
      _commandPhase = 4;
      await _writeCommand(0x0D);
    } else if (_rdtLength == 65) {
      await crypto.setPatchEphemeral(_rdtData);
      await _writeCommand(0x11);
    } else {
      _fail('unexpected cert length ${_rdtLength}');
    }
  }

  /// A fully reassembled challenge transfer: 23 B = r1 + nonce (respond), 67 B =
  /// encrypted `[r2‖r1‖kEnc‖ivEnc]` reply (finish).
  Future<void> _receivedChallenge() async {
    if (_rdtLength == 23) {
      await _respondToChallenge(_rdtData);
    } else if (_rdtLength == 67) {
      await _finishChallenge(_rdtData);
    } else {
      _fail('unexpected challenge length ${_rdtLength}');
    }
  }

  /// Send `enc(r1 ‖ r2 ‖ pin)` back on CHALLENGE_DATA, then command 0x08.
  Future<void> _respondToChallenge(Uint8List challenge23) async {
    _r1.setRange(0, 16, challenge23);
    _nonce1.setRange(0, 7, challenge23, 16);
    for (var index = 0; index < 16; index++) {
      _r2[index] = _random.nextInt(256);
    }
    final payload = Uint8List(36)
      ..setRange(0, 16, _r1)
      ..setRange(16, 32, _r2)
      ..setRange(32, 36, blePin ?? Uint8List(4));
    final encrypted = await crypto.encryptChallenge(_nonce1, payload);
    await _sendFramed(_challengeData!, encrypted);
    await _writeCommand(0x08); // challenge sent
  }

  /// Decrypt the 67-byte reply, verify r1/r2 echo back, derive the AES-CCM
  /// session key/IV + kAuth, and complete the handshake.
  Future<void> _finishChallenge(Uint8List challenge67) async {
    final first = Uint8List.sublistView(challenge67, 0, 60);
    final nonce = Uint8List.sublistView(challenge67, 60, 67);
    final decrypted = await crypto.decryptChallenge(nonce, first);
    if (!_bytesEqual(decrypted, 0, _r2) || !_bytesEqual(decrypted, 16, _r1)) {
      _fail('challenge r1/r2 mismatch');
      return;
    }
    await crypto.initCipher(
      Uint8List.sublistView(decrypted, 32, 48),
      Uint8List.sublistView(decrypted, 48, 56),
    );
    final authKey = await crypto.exportAuthKey();
    if (!_handshake!.isCompleted) {
      _handshake!.complete(authKey);
    }
  }

  bool _bytesEqual(Uint8List haystack, int offset, Uint8List needle) {
    for (var index = 0; index < needle.length; index++) {
      if (haystack[offset + index] != needle[index]) {
        return false;
      }
    }
    return true;
  }

  /// Write one command byte to COMMAND_RESPONSE, then advance the phase from the
  /// write-completion (Juggluco's `oncharwrite`/`sendSecurityCommand`).
  Future<void> _writeCommand(int opcode) async {
    await _securityCommands!.write([opcode], withoutResponse: false);
    switch (_commandPhase) {
      case 1:
        _commandPhase = 2;
        await _writeCommand(0x02);
      case 2:
        _commandPhase = 3;
        await _sendFramed(_certificateData!, await crypto.appCertificate());
      case 4:
        _commandPhase = 5;
        await _sendFramed(_certificateData!, await crypto.generateEphemeralKeys());
      // phases 3 and 5 wait for the next notification.
    }
  }

  /// After a full cert/challenge payload is written, the next command depends on
  /// the phase (Juggluco's `oncharwrite` CERT_DATA branch): mid-exchange after the
  /// app cert (phase 3) send 0x03, after our ephemeral (phase 5) send 0x0E.
  Future<void> _afterCertWritten() async {
    await _writeCommand(_commandPhase == 5 ? 0x0E : 0x03);
  }

  /// Run a handshake step, routing any error to the handshake completer so the
  /// awaiting [runHandshake] fails instead of the exception being swallowed.
  void _drive(Future<void> Function() step) {
    step().catchError((Object error) => _fail('$error'));
  }

  void _fail(String message) {
    _log('Libre 3 handshake failed: $message');
    if (_handshake != null && !_handshake!.isCompleted) {
      _handshake!.completeError(StateError(message));
    }
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

  /// Write a cert/ephemeral/challenge payload to [characteristic] as fixed 20-byte
  /// frames — `[LE16 offset][≤18 data bytes, zero-padded]` — with write-response,
  /// exactly as Juggluco's `writedata`. The sensor expects the fixed size and
  /// rejects write-WITHOUT-response on these characteristics.
  Future<void> _sendFramed(
    BluetoothCharacteristic characteristic,
    Uint8List bytes,
  ) async {
    for (var offset = 0; offset < bytes.length; offset += 18) {
      final end = (offset + 18 < bytes.length) ? offset + 18 : bytes.length;
      final frame = Uint8List(20);
      frame[0] = offset & 0xFF;
      frame[1] = (offset >> 8) & 0xFF;
      frame.setRange(2, 2 + (end - offset), bytes, offset);
      await characteristic.write(frame, withoutResponse: false);
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
