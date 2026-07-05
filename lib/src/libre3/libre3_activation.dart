import 'dart:typed_data';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

/// Everything a FreeStyle Libre 3 hands back over NFC when it is activated. The
/// [bleMac] is how we then find it over BLE; the [blePin] is consumed inside the
/// BLE security handshake; the rest is the sensor session clock.
///
/// Field layout ported verbatim from DiaBLE's `Libre3.parseActivation` (the
/// clean open reference). See docs/LIBRE3.md.
class Libre3ActivationResult {
  Libre3ActivationResult({
    required this.bleMac,
    required this.blePin,
    required this.activationTimeSec,
  });

  /// Colon-separated uppercase BLE MAC, e.g. `C1:23:45:67:89:AB`.
  final String bleMac;

  /// The 4-byte BLE PIN (secret used in the BLE challenge-response).
  final Uint8List blePin;

  /// Unix seconds the sensor recorded as its activation time (session start).
  final int activationTimeSec;
}

/// One NFC scan activates a Libre 3 (or reads back an already-activated one),
/// after which all glucose is delivered over BLE. This runs the ISO 15693
/// exchange on Android (via `NfcV#transceive`) and decodes the response.
///
/// The wire crypto (FNV-32 receiver id, CRC-16, activation-parameter framing,
/// response layout) is a clean-room port of DiaBLE; only the raw ISO 15693 frame
/// flags/manufacturer byte are Abbott-proprietary and MUST be confirmed on a
/// real sensor (marked below) — they cannot be validated without hardware.
class Libre3Activation {
  Libre3Activation({required this.accountId});

  /// The LibreView account GUID. A *fresh* sensor accepts any value; to take
  /// over a sensor already activated by Abbott's app this must be that account's
  /// id (its FNV-32 hash is the receiver id the sensor was bound to).
  final String accountId;

  /// ISO 15693 request flag byte for the addressed custom commands (high data
  /// rate). ponytail: confirmed value; if a sensor NAKs, the addressed/UID flags
  /// are the first thing to check on-device.
  static const _requestFlags = 0x02;

  /// Abbott/TI custom command: read the patch (factory) info.
  static const _cmdReadPatchInfo = 0xA1;

  /// Custom command that activates a fresh sensor (in storage state) and sets a
  /// new BLE PIN. An already-activated sensor is queried with [_cmdQuery].
  static const _cmdActivate = 0xA8;

  /// Custom command that returns the current BLE PIN of an activated sensor.
  static const _cmdQuery = 0xA0;

  /// Patch-state byte value meaning "in storage" (never activated) — decides
  /// whether we send [_cmdActivate] or [_cmdQuery].
  static const _stateStorage = 0x01;

  /// Run the full scan. Completes with the decoded result, or throws on a bad
  /// tag / CRC mismatch / user cancel. The NFC session is always finished.
  Future<Libre3ActivationResult> run() async {
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available) {
      throw StateError('NFC is not available on this device');
    }
    final tag = await FlutterNfcKit.poll(
      readIso15693: true,
      readIso14443A: false,
      readIso14443B: false,
      readIso18092: false,
    );
    try {
      if (tag.type != NFCTagType.iso15693) {
        throw StateError('Tag is not a FreeStyle Libre (ISO 15693)');
      }
      return await _exchange();
    } finally {
      await FlutterNfcKit.finish();
    }
  }

  Future<Libre3ActivationResult> _exchange() async {
    final patchInfo = await _customCommand(_cmdReadPatchInfo, Uint8List(0));
    final activationTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final parameters = buildActivationParameters(
      activationTimeSec: activationTime,
      accountId: accountId,
    );
    final code = (patchInfo.length > 14 && patchInfo[14] == _stateStorage)
        ? _cmdActivate
        : _cmdQuery;
    final response = await _customCommand(code, parameters);
    return parseActivationResponse(response);
  }

  /// Assemble + send an ISO 15693 addressed custom command frame and return the
  /// tag's reply. The frame is `flags | command | manufacturer | params`.
  /// ponytail: the Abbott IC manufacturer code (0x07 = Texas Instruments) is the
  /// one field to re-check if a real sensor rejects the frame — swap it for the
  /// value read from the tag's UID byte [6].
  Future<Uint8List> _customCommand(int command, Uint8List params) async {
    const abbottManufacturer = 0x07;
    final frame = Uint8List.fromList([
      _requestFlags,
      command,
      abbottManufacturer,
      ...params,
    ]);
    return FlutterNfcKit.transceive<Uint8List>(frame);
  }

  // --- pure, testable protocol logic (verbatim from DiaBLE) -----------------

  /// The activation parameters written to the sensor: `(activationTime-1) LE32 ‖
  /// receiverId LE32 ‖ crc16(params) LE16`. The receiver id is [fnv32] of the
  /// LibreView account id.
  static Uint8List buildActivationParameters({
    required int activationTimeSec,
    required String accountId,
  }) {
    final body = BytesBuilder();
    body.add(_le32(activationTimeSec - 1));
    body.add(_le32(fnv32(accountId)));
    final bytes = body.toBytes();
    return Uint8List.fromList([...bytes, ..._le16(crc16(bytes))]);
  }

  /// Decode the 16-byte activation reply (after dropping any leading 0xA5 filler
  /// and the flag byte). Throws on a wrong length or CRC mismatch.
  static Libre3ActivationResult parseActivationResponse(Uint8List output) {
    var start = 0;
    while (start < output.length && output[start] == 0xA5) {
      start++;
    }
    if (start >= output.length) {
      throw StateError('empty NFC activation response');
    }
    final flag = output[start];
    final body = output.sublist(start + 1);
    if (flag != 0x00 || body.length < 16) {
      throw StateError('NFC activation failed (flag=$flag, len=${body.length})');
    }
    final crc = _readLe16(body, 14);
    final computed = crc16(Uint8List.sublistView(body, 0, 14));
    if (crc != computed) {
      throw StateError('NFC activation CRC mismatch');
    }
    final mac = body
        .sublist(0, 6)
        .reversed
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
    return Libre3ActivationResult(
      bleMac: mac,
      blePin: Uint8List.fromList(body.sublist(6, 10)),
      activationTimeSec: _readLe32(body, 10),
    );
  }

  /// FreeStyle receiver-id hash — an FNV-1 variant with a 0-seeded accumulator
  /// and the 0xFFFFFFFF mask, ported verbatim from DiaBLE's `String.fnv32Hash`.
  static int fnv32(String accountId) {
    var hash = 0;
    for (final unit in accountId.codeUnits) {
      hash = ((hash * 0x811C9DC5) & 0xFFFFFFFF) ^ (unit & 0xFF);
      hash &= 0xFFFFFFFF;
    }
    return hash & 0xFFFFFFFF;
  }

  /// The FreeStyle Libre CRC-16 (CCITT/Kermit-style), the same routine used to
  /// validate sensor memory across xDrip/DiaBLE.
  static int crc16(Uint8List data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc = ((crc >> 8) | (crc << 8)) & 0xFFFF;
      crc ^= byte & 0xFF;
      crc ^= (crc & 0xFF) >> 4;
      crc ^= (crc << 12) & 0xFFFF;
      crc ^= (crc & 0xFF) << 5;
      crc &= 0xFFFF;
    }
    return crc & 0xFFFF;
  }

  static Uint8List _le16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

  static Uint8List _le32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value & 0xFFFFFFFF, Endian.little);

  static int _readLe16(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  static int _readLe32(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
