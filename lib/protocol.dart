// Dexcom G7 BLE Protokoll-Implementierung
// Basiert auf xDrip+ Open Source (NightscoutFoundation/xDrip)
// Lizenz: AGPLv3

import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// ─── GATT UUIDs ────────────────────────────────────────────────────────────
class DexcomUUIDs {
  static const cgmService     = 'f8083532-849e-531c-c594-30f1f86a4ea5';
  static const communication  = 'f8083533-849e-531c-c594-30f1f86a4ea5';
  static const control        = 'f8083534-849e-531c-c594-30f1f86a4ea5';
  static const authentication = 'f8083535-849e-531c-c594-30f1f86a4ea5';
  static const backfill       = 'f8083536-849e-531c-c594-30f1f86a4ea5';
  static const extraData      = 'f8083538-849e-531c-c594-30f1f86a4ea5';
}

// ─── OPCODES ───────────────────────────────────────────────────────────────
class Opcode {
  static const authRequest   = 0x01;
  static const authChallenge = 0x03;
  static const authResponse  = 0x04;
  static const authStatus    = 0x05;
  static const keepAlive     = 0x06;
  static const disconnect    = 0x09;
  static const eGlucoseTx   = 0x4e;
  static const eGlucoseRx   = 0x4e;
}

// ─── CRYPTO ────────────────────────────────────────────────────────────────
class DexcomCrypto {
  /// Leitet den 16-Byte AES-Schlüssel aus der Transmitter-ID ab.
  /// G6: 6-stellige alphanumerische Transmitter-ID.
  /// G7: 4-stelliger Pairing-Code – wird auf 6 Stellen mit führenden
  /// Nullen aufgefüllt, damit dieselbe Formel wie bei G6 exakt 16 Bytes
  /// ergibt (vgl. LoopKit/CGMBLEKit: `"00\(id)00\(id)"` mit 6-stelliger id).
  /// Schlüssel = UTF-8("00" + id + "00" + id), immer 16 Bytes.
  static Uint8List buildKey(String transmitterId) {
    final id = transmitterId.padLeft(6, '0');
    final keyStr = '00$id' '00$id';
    return Uint8List.fromList(keyStr.codeUnits);
  }

  /// Leitet den 16-Byte AES-Schlüssel aus dem Pairing-Code ab.
  /// G7 verwendet (wie G5/G6 in xDrip+) das Muster "00<code>00<code>"
  /// als UTF-8-Bytes für den AES-128-Schlüssel. Die Seriennummer fließt
  /// NICHT in den Schlüssel ein – sie dient nur zur Geräte-Identifikation.
  /// Quelle: xDrip+/DiaBLE-Reverseengineering der legacy Auth-Challenge,
  /// die hier auch tatsächlich vom Sensor genutzt wird (Opcode 0x03).
  static Uint8List buildKeyFromCodeAndSerial(
      String sensorCode, String serialNumber) {
    return buildKey(sensorCode);
  }

  /// Berechnet den Challenge-Response mit AES-128-ECB.
  /// challenge: 8 Bytes vom Sensor
  /// → plaintext = challenge + challenge (16 Bytes)
  /// → AES-ECB encrypt → erste 8 Bytes zurück
  static Uint8List calculateChallengeResponse(
      Uint8List challenge, Uint8List key) {
    assert(challenge.length == 8, 'Challenge muss 8 Bytes sein');
    assert(key.length == 16, 'Schlüssel muss 16 Bytes sein');

    // Plaintext: challenge duplizieren
    final plainText = Uint8List(16);
    plainText.setRange(0, 8, challenge);
    plainText.setRange(8, 16, challenge);

    // AES-ECB (kein Padding nötig, exakt 16 Bytes)
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, KeyParameter(key));

    final cipherText = Uint8List(16);
    cipher.processBlock(plainText, 0, cipherText, 0);

    // Nur erste 8 Bytes zurückgeben
    return cipherText.sublist(0, 8);
  }

  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => rng.nextInt(256)));
  }
}

// ─── NACHRICHTEN (TX) ──────────────────────────────────────────────────────

/// AuthRequest → an Authentication Characteristic schreiben
/// [0x01][8 random bytes][0x02]
class AuthRequestTx {
  final Uint8List singleUseToken;

  AuthRequestTx() : singleUseToken = DexcomCrypto.randomBytes(8);

  Uint8List get bytes {
    final buf = ByteData(10);
    buf.setUint8(0, Opcode.authRequest);
    final b = buf.buffer.asUint8List();
    b.setRange(1, 9, singleUseToken);
    b[9] = 0x02; // slot/end byte
    return b;
  }
}

/// AuthChallengeResponse → antwortet auf die Challenge
/// [0x04][8 Bytes response hash]
class AuthChallengeTx {
  final Uint8List challengeHash;

  AuthChallengeTx(this.challengeHash);

  Uint8List get bytes {
    assert(challengeHash.length == 8);
    final b = Uint8List(9);
    b[0] = Opcode.authResponse;
    b.setRange(1, 9, challengeHash);
    return b;
  }
}

/// KeepAlive → verhindert Timeout während Auth
/// [0x06][time in seconds]
class KeepAliveTx {
  final int seconds;
  KeepAliveTx([this.seconds = 60]);

  Uint8List get bytes => Uint8List.fromList([Opcode.keepAlive, seconds]);
}

/// EGlucoseTx → fordert Glukosewert an (G7: kein CRC, nur 1 Byte)
class EGlucoseTx {
  Uint8List get bytes => Uint8List.fromList([Opcode.eGlucoseTx]);
}

/// Disconnect
class DisconnectTx {
  Uint8List get bytes => Uint8List.fromList([Opcode.disconnect]);
}

// ─── NACHRICHTEN (RX) ──────────────────────────────────────────────────────

/// AuthChallengeRx → empfangen von Authentication Characteristic
/// [0x03][8 token hash][8 challenge bytes]
class AuthChallengeRx {
  final Uint8List tokenHash;
  final Uint8List challenge;

  AuthChallengeRx._(this.tokenHash, this.challenge);

  static AuthChallengeRx? parse(Uint8List data) {
    if (data.length < 17 || data[0] != Opcode.authChallenge) return null;
    return AuthChallengeRx._(
      data.sublist(1, 9),
      data.sublist(9, 17),
    );
  }
}

/// AuthStatusRx → Ergebnis der Authentifizierung
/// [0x05][authenticated: 0/1][bonded: 0/1]
class AuthStatusRx {
  final bool authenticated;
  final bool bonded;

  AuthStatusRx._(this.authenticated, this.bonded);

  static AuthStatusRx? parse(Uint8List data) {
    if (data.length < 3 || data[0] != Opcode.authStatus) return null;
    return AuthStatusRx._(data[1] == 1, data[2] == 1);
  }
}

/// EGlucoseRx → Glukosewert vom Sensor (G7 Format)
/// Opcode: 0x4e
/// Layout (Little-Endian):
/// [0]    opcode
/// [1]    status_raw
/// [2-5]  clock (uint32) - interne Zeit des Sensors
/// [6-7]  sequence (uint16)
/// [8-9]  bogus/reserved (uint16)
/// [10-11] age (uint16) - Sekunden seit letzter Messung
/// [12-13] glucose bytes (int16) - Bits 0-11 = mg/dL, Bit 12 = displayOnly
/// [14]   calibration state
/// [15]   trend (1/10 mg/dL/min, 127 = ungültig)
/// [16-17] predicted glucose (int16, Bits 0-9, 0x3FF = ungültig)
/// [18]   info
class EGlucoseRx {
  final int statusRaw;
  final int clock;
  final int sequence;
  final int age;           // Sekunden
  final int glucose;       // mg/dL
  final bool displayOnly;
  final int calibrationState;
  final int trendRaw;
  final int? predictedGlucose;
  final DateTime timestamp;

  EGlucoseRx._({
    required this.statusRaw,
    required this.clock,
    required this.sequence,
    required this.age,
    required this.glucose,
    required this.displayOnly,
    required this.calibrationState,
    required this.trendRaw,
    required this.predictedGlucose,
    required this.timestamp,
  });

  static EGlucoseRx? parse(Uint8List data) {
    if (data.length < 19 || data[0] != Opcode.eGlucoseRx) return null;

    final bd = ByteData.sublistView(data);
    int offset = 0;

    final opcode = bd.getUint8(offset++);
    if (opcode != Opcode.eGlucoseRx) return null;

    final statusRaw = bd.getUint8(offset++);
    final clock = bd.getUint32(offset, Endian.little); offset += 4;
    final sequence = bd.getUint16(offset, Endian.little); offset += 2;
    offset += 2; // bogus/reserved

    final age = bd.getUint16(offset, Endian.little); offset += 2;

    final glucoseBytes = bd.getInt16(offset, Endian.little); offset += 2;
    final displayOnly = (glucoseBytes & 0xf000) != 0;
    final glucose = glucoseBytes & 0x0fff;

    final calibrationState = bd.getUint8(offset++);
    final trendRaw = bd.getUint8(offset++);

    int? predictedGlucose;
    if (data.length > offset + 1) {
      final predRaw = bd.getInt16(offset, Endian.little) & 0x03ff;
      if (predRaw != 0x3ff) predictedGlucose = predRaw;
    }

    final timestamp = DateTime.now().subtract(Duration(seconds: age));

    return EGlucoseRx._(
      statusRaw: statusRaw,
      clock: clock,
      sequence: sequence,
      age: age,
      glucose: glucose,
      displayOnly: displayOnly,
      calibrationState: calibrationState,
      trendRaw: trendRaw,
      predictedGlucose: predictedGlucose,
      timestamp: timestamp,
    );
  }

  /// Trend in mg/dL pro Minute (null wenn ungültig)
  double? get trendMgdlPerMin =>
      trendRaw != 127 ? trendRaw / 10.0 : null;

  /// Trend als Pfeil-Symbol
  String get trendArrow {
    final t = trendMgdlPerMin;
    if (t == null) return '→';
    if (t > 3.0) return '↑↑';
    if (t > 2.0) return '↑';
    if (t > 1.0) return '↗';
    if (t > -1.0) return '→';
    if (t > -2.0) return '↘';
    if (t > -3.0) return '↓';
    return '↓↓';
  }

  /// Kalibrierungszustand als Text
  String get calibrationStateText {
    // CalibrationState aus xDrip (vereinfacht)
    switch (calibrationState & 0x1f) {
      case 0x00: return 'Aufwärmphase';
      case 0x01: return 'OK';
      case 0x02: return 'Kalibrierung nötig';
      case 0x04: return 'Kalibrierung nötig';
      case 0x06: return 'OK';
      case 0x0a: return 'OK';
      case 0x0c: return 'OK';
      default:   return 'Status: 0x${calibrationState.toRadixString(16)}';
    }
  }

  bool get isUsable =>
      glucose > 13 &&
          !displayOnly &&
          [0x01, 0x06, 0x0a, 0x0c].contains(calibrationState & 0x1f);

  bool get isWarmingUp =>
      [0x00].contains(calibrationState & 0x1f);

  @override
  String toString() =>
      'Glukose: ${glucose} mg/dL $trendArrow | '
          'Alter: ${age}s | Seq: $sequence | '
          'Status: $calibrationStateText';
}

// ─── PACKET CLASSIFIER ─────────────────────────────────────────────────────
sealed class DexcomPacket {}

class AuthChallengePacket extends DexcomPacket {
  final AuthChallengeRx msg;
  AuthChallengePacket(this.msg);
}

class AuthStatusPacket extends DexcomPacket {
  final AuthStatusRx msg;
  AuthStatusPacket(this.msg);
}

class GlucosePacket extends DexcomPacket {
  final EGlucoseRx msg;
  GlucosePacket(this.msg);
}

class UnknownPacket extends DexcomPacket {
  final Uint8List data;
  UnknownPacket(this.data);
}

DexcomPacket classifyPacket(Uint8List data) {
  if (data.isEmpty) return UnknownPacket(data);

  switch (data[0]) {
    case Opcode.authChallenge:
      final msg = AuthChallengeRx.parse(data);
      if (msg != null) return AuthChallengePacket(msg);
    case Opcode.authStatus:
      final msg = AuthStatusRx.parse(data);
      if (msg != null) return AuthStatusPacket(msg);
    case Opcode.eGlucoseRx:
      final msg = EGlucoseRx.parse(data);
      if (msg != null) return GlucosePacket(msg);
  }

  return UnknownPacket(data);
}