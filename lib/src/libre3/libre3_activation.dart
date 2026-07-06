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
/// The command framing (flags/command/manufacturer), command selection and the
/// activation-parameter layout (incl. the non-standard CRC-16) are ported from
/// Juggluco's Libre 3 NFC code (`libre3/NFC.java` + `dp_activation.hpp`) — the
/// GPL upstream that actually works on real Libre 3 hardware. See docs/LIBRE3.md.
class Libre3Activation {
  Libre3Activation({required this.accountId});

  /// The LibreView account NUMBER (a decimal integer). Its low 32 bits become
  /// the receiver id the sensor is bound to. A fresh sensor is activated under
  /// this id and later queried with the same id (so it must stay stable).
  /// (Juggluco's `getlibreAccountIDnumber()`.)
  final String accountId;

  /// The sensor rejects account 0 (Juggluco refuses `getlibreAccountIDnumber()
  /// == 0` with a "zero account ID" error), but does NOT validate the value
  /// against Abbott's cloud over NFC — any non-zero id it can bind to works for
  /// local reading. So a blank/zero field falls back to this fixed non-zero id;
  /// a real LibreView number only matters for LibreView cloud sync (unused here).
  static const _defaultAccount = 0x4A554755; // "JUGU" — arbitrary, stable, != 0

  int get _account {
    final parsed = int.tryParse(accountId.trim()) ?? 0;
    return parsed != 0 ? parsed & 0xFFFFFFFF : _defaultAccount;
  }

  /// ISO 15693 request flag byte (high data rate, unaddressed) — Juggluco's
  /// leading `0x02` for every Libre 3 custom command.
  static const _requestFlags = 0x02;

  /// Custom command: read the patch (factory) info.
  static const _cmdReadPatchInfo = 0xA1;

  /// Command sent when the patch-info discriminator byte [_stateIndex] is NOT 1
  /// (Juggluco's `nfc1[17]!=1` branch).
  static const _cmdActivate = 0xA8;

  /// Command sent when the patch-info discriminator byte [_stateIndex] IS 1
  /// (Juggluco's `nfc1[17]==1` branch).
  static const _cmdQuery = 0xA0;

  /// Index into the raw patch-info reply (flag byte included) whose value picks
  /// [_cmdQuery] vs [_cmdActivate] — Juggluco reads `nfc1[17]`.
  static const _stateIndex = 17;

  /// IC manufacturer code sent in every custom-command frame. ISO 15693 custom
  /// commands (`0xA0–0xDF`) require the tag's OWN manufacturer code or the IC
  /// rejects the command — so this is read from the polled UID in [run]. `0x07`
  /// (Texas Instruments, the Libre 1/2 chip) is only the fallback; the real
  /// Libre 3 reports `0x7A`.
  int _manufacturer = 0x07;

  /// Abort an in-progress [run] — e.g. the user dismissed the scan sheet. The
  /// pending NFC poll then throws and [run] unwinds through its `finally`.
  static Future<void> abort() async {
    try {
      await FlutterNfcKit.finish();
    } catch (_) {}
  }

  /// Run the full scan. Completes with the decoded result, or throws on a bad
  /// tag / rejected command / CRC mismatch / user cancel. Any error is tagged
  /// with the sensor UID for on-device bring-up. The NFC session is always
  /// finished.
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
      _manufacturer = manufacturerFromUid(tag.id) ?? _manufacturer;
      return await _exchange();
    } catch (error) {
      throw StateError('$error · uid=${tag.id}');
    } finally {
      await FlutterNfcKit.finish();
    }
  }

  /// The IC manufacturer code (UID byte 6) of a polled ISO 15693 tag. Android
  /// returns the 8-byte UID with the `0xE0` tag byte LAST, so the manufacturer
  /// is the second-to-last byte. Null if the UID isn't the expected 8-byte
  /// `0xE0`-terminated form, so [run] keeps the fallback.
  static int? manufacturerFromUid(String uid) {
    final bytes = _hexToBytes(uid);
    if (bytes.length != 8 || bytes.last != 0xE0) {
      return null;
    }
    return bytes[6];
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    if (clean.length.isOdd) {
      return Uint8List(0);
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var index = 0; index < out.length; index++) {
      out[index] = int.parse(
        clean.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return out;
  }

  Future<Libre3ActivationResult> _exchange() async {
    final patchInfo = await _customCommand(_cmdReadPatchInfo, Uint8List(0));
    throwIfNfcError('read patch info (0xa1)', Uint8List(0), patchInfo);
    final activationTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final parameters = buildActivationParameters(
      activationTimeSec: activationTime,
      account: _account,
    );
    final code = (patchInfo.length > _stateIndex && patchInfo[_stateIndex] == 1)
        ? _cmdQuery
        : _cmdActivate;
    final response = await _customCommand(code, parameters);
    try {
      throwIfNfcError('command 0x${code.toRadixString(16)}', parameters, response);
    } on StateError catch (error) {
      throw StateError('${error.message} · patchInfo=${hex(patchInfo)}');
    }
    return parseActivationResponse(response);
  }

  /// Throw if a custom-command reply carries the ISO 15693 error flag (bit 0 of
  /// the leading response byte, after any 0xA5 filler). The [label], sent
  /// [params] and raw [response] are dumped so the failing frame is visible
  /// on-device — this whole NFC command set is a hardware-unverified port.
  static void throwIfNfcError(
    String label,
    Uint8List params,
    Uint8List response,
  ) {
    var start = 0;
    while (start < response.length && response[start] == 0xA5) {
      start++;
    }
    if (start < response.length && (response[start] & 0x01) != 0) {
      final code = start + 1 < response.length ? response[start + 1] : -1;
      throw StateError(
        '$label rejected (ISO error 0x'
        '${code.toRadixString(16).padLeft(2, '0')}) · '
        'params=${hex(params)} · resp=${hex(response)}',
      );
    }
  }

  /// Lowercase space-separated hex dump, for surfacing raw NFC frames in error
  /// messages during on-device protocol bring-up.
  static String hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Assemble + send an ISO 15693 custom command frame and return the tag's
  /// reply. The frame is `flags | command | manufacturer | params`, where
  /// [_manufacturer] is the code read from the sensor's own UID (see [run]).
  Future<Uint8List> _customCommand(int command, Uint8List params) async {
    final frame = Uint8List.fromList([
      _requestFlags,
      command,
      _manufacturer,
      ...params,
    ]);
    return FlutterNfcKit.transceive<Uint8List>(frame);
  }

  // --- pure, testable protocol logic (ported from Juggluco) -----------------

  /// The 10-byte activation parameter block, byte-for-byte per Juggluco's
  /// `DPGetActivationCommandData` (`dp_activation.hpp`):
  ///   `[0..4) = (activationTime-1) LE32`
  ///   `[4..8) = account LE32`
  ///   `[8..10) = crc16Activation([0..8)) LE16`.
  static Uint8List buildActivationParameters({
    required int activationTimeSec,
    required int account,
  }) {
    final out = Uint8List(10);
    final view = ByteData.view(out.buffer);
    view.setUint32(0, (activationTimeSec - 1) & 0xFFFFFFFF, Endian.little);
    view.setUint32(4, account & 0xFFFFFFFF, Endian.little);
    view.setUint16(8, crc16Activation(Uint8List.sublistView(out, 0, 8)),
        Endian.little);
    return out;
  }

  /// The activation CRC-16 Juggluco uses (`dp_activation.hpp`): poly `0x1021`,
  /// init `0xFFFF`, refin=true (each input byte bit-reversed), refout=false,
  /// xorout=0. NOT the FreeStyle Kermit [crc16]. Verified against Juggluco's
  /// static-assert vectors in the tests.
  static int crc16Activation(Uint8List data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc = (crc ^ (_bitrev8(byte) << 8)) & 0xFFFF;
      for (var bit = 0; bit < 8; bit++) {
        final shifted = (crc << 1) & 0xFFFF;
        crc = (crc & 0x8000) != 0 ? shifted ^ 0x1021 : shifted;
      }
    }
    return crc & 0xFFFF;
  }

  static int _bitrev8(int byte) {
    var value = byte & 0xFF;
    value = ((value & 0xF0) >> 4) | ((value & 0x0F) << 4);
    value = ((value & 0xCC) >> 2) | ((value & 0x33) << 2);
    value = ((value & 0xAA) >> 1) | ((value & 0x55) << 1);
    return value & 0xFF;
  }

  /// Decode the activation reply per Juggluco's `nfc2` struct (`nfc.cpp`), a
  /// packed 19-byte layout:
  ///   `[0]      zero`            — ISO success flag (0x00)
  ///   `[1..3)   response`        — 2 bytes, ignored
  ///   `[3..9)   deviceAddress`   — BLE MAC, reversed on the wire
  ///   `[9..13)  pin`             — BLE PIN (4 bytes)
  ///   `[13..17) activationTime`  — UInt32 LE
  ///   `[17..19) crc16`           — NOT verified (Juggluco's parser doesn't)
  /// A 4-byte reply is Juggluco's `nfc2error` (`00 A5 01 <code>`).
  static Libre3ActivationResult parseActivationResponse(Uint8List output) {
    if (output.length == 4 && output[3] != 0) {
      throw StateError(
        'sensor rejected activation (app error 0x'
        '${output[3].toRadixString(16).padLeft(2, '0')}) · resp=${hex(output)}',
      );
    }
    if (output.length < 19) {
      throw StateError(
        'unexpected activation response (len=${output.length}) · '
        'resp=${hex(output)}',
      );
    }
    final mac = output
        .sublist(3, 9)
        .reversed
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
    return Libre3ActivationResult(
      bleMac: mac,
      blePin: Uint8List.fromList(output.sublist(9, 13)),
      activationTimeSec: _readLe32(output, 13),
    );
  }

  static int _readLe32(Uint8List data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}
