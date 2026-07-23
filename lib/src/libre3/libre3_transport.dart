import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'libre3_crypto.dart';
import 'libre3_security_transfer.dart';
import 'libre3_uuids.dart';

/// flutter_blue_plus transport + security handshake for the FreeStyle Libre 3.
///
/// The BLE plumbing (scan-by-MAC, discover, subscribe, MTU) mirrors the G7's
/// [BleTransport]. The handshake is a clean-room port of Juggluco's
/// `Libre3GattCallback` ordered sequence; every crypto primitive is delegated to
/// [Libre3Crypto] (the Abbott blob). See docs/LIBRE3.md for the byte-level flow.
///
/// The ordering below follows Juggluco and has completed against a real sensor;
/// incoming fragment reassembly is [Libre3SecurityTransfer], which tolerates a
/// padded final frame and fails fast on a framing violation.
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
  BluetoothCharacteristic? _clinicalData;
  BluetoothCharacteristic? _eventLog;
  BluetoothCharacteristic? _factoryData;

  final _glucoseRx = StreamController<Uint8List>.broadcast();
  final _historicRx = StreamController<Uint8List>.broadcast();
  final _clinicalRx = StreamController<Uint8List>.broadcast();

  /// Decrypted one-minute glucose payloads.
  Stream<Uint8List> get glucoseStream => _glucoseRx.stream;

  /// Decrypted historical (backfill, 5-min) payloads.
  Stream<Uint8List> get historicStream => _historicRx.stream;

  /// Decrypted clinical (1-min, 2-hour buffer) payloads.
  Stream<Uint8List> get clinicalStream => _clinicalRx.stream;

  final List<StreamSubscription> _subs = [];

  // --- security handshake state (Juggluco's Libre3GattCallback) -------------
  // Command phase, advanced by COMMAND_RESPONSE write-completions.
  int _commandPhase = 1;
  // Reassembly of a cert/challenge transfer whose length COMMAND_RESPONSE
  // announced via preparedata; fragments carry an incrementing sequence byte.
  final Libre3SecurityTransfer _transfer = Libre3SecurityTransfer();
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
      case Libre3Uuids.clinicalData:
        _clinicalData = characteristic;
      case Libre3Uuids.eventLog:
        _eventLog = characteristic;
      case Libre3Uuids.factoryData:
        _factoryData = characteristic;
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
    await _subscribe(
      _certificateData!,
      (value) => _onSecData(value, _receivedCert),
    );
    await _subscribe(
      _challengeData!,
      (value) => _onSecData(value, _receivedChallenge),
    );
    await crypto.initKeys(cachedAuthKey, securityVersion);

    if (cachedAuthKey != null) {
      _commandPhase = 5;
      _drive(
        () => _writeCommand(0x11),
      ); // pre-authorised: straight to challenge
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
    _transfer.expect(length);
  }

  /// A CERT_DATA / CHALLENGE_DATA fragment: `[sequence, ...data]`. Reassembles
  /// through [_transfer]; when the announced length is complete, runs
  /// [onComplete] (Juggluco's `getsecdata`). A framing violation throws inside a
  /// notification listener, where an escaping error would leave the handshake
  /// hanging until its timeout — so it is caught and routed to [_fail].
  void _onSecData(List<int> value, Future<void> Function() onComplete) {
    try {
      if (_transfer.add(value)) {
        _drive(onComplete);
      }
    } on Libre3TransferException catch (error) {
      _fail(error.message);
    }
  }

  /// A fully reassembled cert transfer: 140 B = sensor patch cert, 65 B = sensor
  /// ephemeral public key.
  Future<void> _receivedCert() async {
    _log('Libre 3 received cert transfer (${_transfer.length} B)');
    if (_transfer.length == 140) {
      await crypto.setPatchCertificate(_transfer.data);
      _commandPhase = 4;
      await _writeCommand(0x0D);
    } else if (_transfer.length == 65) {
      await crypto.setPatchEphemeral(_transfer.data);
      await _writeCommand(0x11);
    } else {
      _fail('unexpected cert length ${_transfer.length}');
    }
  }

  /// A fully reassembled challenge transfer: 23 B = r1 + nonce (respond), 67 B =
  /// encrypted `[r2‖r1‖kEnc‖ivEnc]` reply (finish).
  Future<void> _receivedChallenge() async {
    if (_transfer.length == 23) {
      await _respondToChallenge(_transfer.data);
    } else if (_transfer.length == 67) {
      await _finishChallenge(_transfer.data);
    } else {
      _fail('unexpected challenge length ${_transfer.length}');
    }
  }

  /// Send `enc(r1 ‖ r2 ‖ pin)` back on CHALLENGE_DATA, then command 0x08.
  ///
  /// The PIN is the one input the sensor validates that we cannot derive — a
  /// missing one used to be sent as four zero bytes, which the sensor rejects by
  /// terminating the link (indistinguishable from a crypto bug). Fail loudly and
  /// log the PIN so a wrong/stale one is visible in the handshake log.
  Future<void> _respondToChallenge(Uint8List challenge23) async {
    final pin = blePin;
    if (pin == null || pin.length != 4) {
      _fail('no BLE PIN on file — scan the sensor with NFC');
      return;
    }
    _r1.setRange(0, 16, challenge23);
    _nonce1.setRange(0, 7, challenge23, 16);
    for (var index = 0; index < 16; index++) {
      _r2[index] = _random.nextInt(256);
    }
    final payload = Uint8List(36)
      ..setRange(0, 16, _r1)
      ..setRange(16, 32, _r2)
      ..setRange(32, 36, pin);
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
        final appCert = await crypto.appCertificate();
        _log('Libre 3 sending app cert (${appCert.length} B)');
        await _sendFramed(_certificateData!, appCert);
        await _afterCertWritten();
      case 4:
        _commandPhase = 5;
        final ephemeral = _uncompressedPoint(
          await crypto.generateEphemeralKeys(),
        );
        _log('Libre 3 sending ephemeral (${ephemeral.length} B)');
        await _sendFramed(_certificateData!, ephemeral);
        await _afterCertWritten();
      // phases 3 and 5 wait for the next notification.
    }
  }

  /// The blob emits the ephemeral P-256 public key as a raw 64-byte point (X‖Y).
  /// The sensor exchanges keys in SEC1 uncompressed form (its own ephemeral is
  /// 65 B = `0x04‖X‖Y`), so prepend the `0x04` marker to match — without it the
  /// ECDH key agreement fails and the sensor drops the link after `0x0E`.
  Uint8List _uncompressedPoint(Uint8List point) {
    if (point.length != 64) {
      return point;
    }
    return Uint8List(65)
      ..[0] = 0x04
      ..setRange(1, 65, point);
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

  /// Enable notifications on the FULL data-service set, in the documented order
  /// (`docs/LIBRE3.md`: PATCH_CONTROL → … → GLUCOSE → PATCH_STATUS, status last).
  /// The Libre withheld its historic stream while only a subset was subscribed;
  /// the sensor likely gates delivery on the complete notify set. glucose (ch3)
  /// and historic (ch4) go through the AES-CCM decrypt; the rest are OBSERVE-ONLY
  /// (raw-logged) because their channel/format is unknown — if the missed data
  /// actually rides one of them, the log reveals which.
  Future<void> _enableDataChannels() async {
    await _observe(_patchControl, 'patchControl');
    if (_historic != null) {
      await _subscribeLogged(
        _historic!,
        'historic',
        (data) => _decryptInto(Libre3Uuids.decryptHistoric, data, _historicRx),
      );
    }
    if (_clinicalData != null) {
      await _subscribeLogged(
        _clinicalData!,
        'clinical',
        (data) => _decryptInto(Libre3Uuids.decryptClinical, data, _clinicalRx),
      );
    }
    await _observe(_eventLog, 'eventLog');
    await _observe(_factoryData, 'factoryData');
    if (_oneMinute != null) {
      await _subscribeLogged(
        _oneMinute!,
        'glucose',
        (data) => _decryptInto(Libre3Uuids.decryptGlucose, data, _glucoseRx),
      );
    }
    await _observe(_patchStatus, 'patchStatus');
  }

  /// Subscribe an observe-only characteristic: log every notification's raw hex
  /// (we don't know its decrypt channel), so a silent historic stream that
  /// actually surfaces here becomes visible on-device.
  Future<void> _observe(
    BluetoothCharacteristic? characteristic,
    String name,
  ) async {
    if (characteristic == null) {
      return;
    }
    await _subscribeLogged(
      characteristic,
      name,
      (data) => _log('Libre 3 $name notify: ${_hex(data)}'),
    );
  }

  /// [_subscribe] plus a log line confirming the characteristic was notify-enabled.
  Future<void> _subscribeLogged(
    BluetoothCharacteristic characteristic,
    String name,
    void Function(List<int>) onData,
  ) async {
    await _subscribe(characteristic, onData);
    _log('Libre 3 enabled notify: $name (${characteristic.uuid.str})');
  }

  /// Ask the patch to replay its **5-minute historic** buffer from
  /// [fromLifeCount] onward (snapped to a boundary by [historicBoundary]), so a
  /// gap left by a disconnect is filled from the sensor's own buffer. Replies
  /// land in [historicStream]. Older data only — the historic buffer lags the
  /// live edge by ~18 min, so recent gaps use [requestClinical] instead.
  Future<void> requestBackfill(int fromLifeCount) => _sendControlCommand(
    _controlCommand(0, historicBoundary(fromLifeCount)),
    'backfill',
  );

  /// Ask the patch to replay its **1-minute clinical** buffer (2 hours deep)
  /// from [fromLifeCount] onward — the minute-by-minute source that fills a
  /// recent reconnect gap the lagging historic buffer can't. Replies land in
  /// [clinicalStream]. Ported from Juggluco's `fillClinical` →
  /// `Natives.libre3ClinicalControl(1, from)` (`kind={1,1}`).
  Future<void> requestClinical(int fromLifeCount) => _sendControlCommand(
    _controlCommand(1, fromLifeCount),
    'clinical',
  );

  /// Encrypt a patch-control command and write it **raw** (`setValue(encr)`,
  /// with response — Juggluco's `sendcommandonly`), NOT the 2-byte-offset 20-byte
  /// framing the cert/challenge writes use ([_sendFramed]); framing it trips
  /// `GATT_INVALID_ATTRIBUTE_LENGTH`.
  Future<void> _sendControlCommand(Uint8List plain, String label) async {
    final control = _patchControl;
    if (control == null) {
      _log('Libre 3 $label: no patch-control characteristic bound');
      return;
    }
    try {
      final encrypted = await crypto.encrypt(Libre3Uuids.encryptControl, plain);
      _log('Libre 3 $label: patch-control ${_hex(plain)} → enc ${encrypted.length} B');
      await control.write(encrypted, withoutResponse: false);
      _log('Libre 3 $label: patch-control write ok');
    } catch (error) {
      _log('Libre 3 $label: patch-control write FAILED ($error)');
    }
  }

  /// The plaintext patch-control request, byte-exact to Juggluco's `RequestData`
  /// struct (`{ kind={1,[kind1]}, arg=1, from }`, packed little-endian):
  /// `01 <kind1> 01 <from as int32 LE>` = 7 bytes. [kind1] is 0 for the 5-min
  /// history (`ControlHistory`), 1 for the 1-min clinical (`ClinicalControl`).
  static Uint8List _controlCommand(int kind1, int from) {
    final command = Uint8List(7);
    command[0] = 0x01;
    command[1] = kind1;
    command[2] = 0x01;
    ByteData.sublistView(command).setInt32(3, from, Endian.little);
    return command;
  }

  /// The 5-minute historic-buffer boundary at/just below [fromLifeCount], byte
  /// -exact to Juggluco's `fillHistory`: `((from - 16) / 5) * 5`. The sensor's
  /// historic buffer is keyed at 5-minute steps, so an unsnapped start returns
  /// no records; the 16-count margin makes the request reach back far enough to
  /// include the boundary that covers the gap. Never negative.
  @visibleForTesting
  static int historicBoundary(int fromLifeCount) {
    final snapped = ((fromLifeCount - 16) ~/ 5) * 5;
    return snapped < 0 ? 0 : snapped;
  }

  /// Reassemble the data notifications before decrypting. At MTU 23 a reading
  /// (~35 B encrypted) arrives split across several ≤20-byte notifications, so a
  /// single fragment never MAC-verifies. AES-CCM only authenticates the COMPLETE
  /// ciphertext+tag, which gives a clean boundary rule: append each fragment and
  /// try to decrypt — a successful MAC means the packet is whole (emit + clear);
  /// a failure means keep accumulating. The buffer resets past [_maxDataPacket]
  /// so a lost fragment can't desync the stream forever.
  static const _maxDataPacket = 60;
  final Map<int, List<int>> _dataBuffers = {};

  Future<void> _decryptInto(
    int channelId,
    List<int> data,
    StreamController<Uint8List> sink,
  ) async {
    final buffer = _dataBuffers.putIfAbsent(channelId, () => <int>[])
      ..addAll(data);
    try {
      final plain = await crypto.decrypt(channelId, Uint8List.fromList(buffer));
      _log(
        'Libre 3 decrypted ch$channelId: ${buffer.length}→${plain.length} B',
      );
      buffer.clear();
      sink.add(plain);
    } catch (error) {
      if (buffer.length >= _maxDataPacket) {
        _log(
          'Libre 3 decrypt ch$channelId gave up at ${buffer.length} B: $error',
        );
        buffer.clear();
      }
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

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
    await _clinicalRx.close();
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
