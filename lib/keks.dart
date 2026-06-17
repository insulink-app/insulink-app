// Dexcom G7 / ONE+ Authentifizierung — EC-J-PAKE ("keks")
//
// Dart-Port von xDrip+ `libkeks` (jamorham/keks, AGPLv3,
// NightscoutFoundation/xDrip). Der moderne G7 leitet KEINEN statischen
// AES-Schlüssel aus dem Pairing-Code ab (das ist das Legacy-G5/G6-Verfahren in
// `protocol.dart`). Stattdessen handeln Sensor und App über EC-J-PAKE
// (Password Authenticated Key Exchange by Juggling) auf der Kurve secp256r1
// einen Sitzungsschlüssel aus dem 4-/6-stelligen Pairing-Code aus. Mit diesem
// Schlüssel wird anschließend die 8-Byte-Challenge per AES-ECB beantwortet.
//
// Referenz J-PAKE: https://ia.cr/2010/190
//
// Dieser Port deckt den J-PAKE-Pfad ab (für bereits gebondete Sensoren).
// Der Zertifikats-/QR-Pfad (erstmaliges Pairing eines ungebondeten Sensors,
// SendCertificate*/SignChallenge + ECDSA) ist NICHT portiert — siehe
// [KeksPlugin]-Zustand `certificateNeeded`.

import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// ─── Kurve secp256r1 (NIST P-256) ────────────────────────────────────────────
final ECDomainParameters _curve = ECCurve_secp256r1();
ECPoint get _g => _curve.G;
BigInt get _qOrder => _curve.n; // Gruppenordnung
const int _fieldSize = 32; // (256 + 7) / 8
const int _packetSize = _fieldSize * 5; // 160

final Random _rng = Random.secure();

// ─── Byte-/BigInt-Helfer ─────────────────────────────────────────────────────
BigInt _bytesToBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b & 0xff);
  }
  return r;
}

Uint8List _bigIntToBytes(BigInt v, int length) {
  final out = Uint8List(length);
  var tmp = v;
  for (int i = length - 1; i >= 0; i--) {
    out[i] = (tmp & BigInt.from(0xff)).toInt();
    tmp = tmp >> 8;
  }
  return out;
}

Uint8List _int32be(int value) {
  final b = Uint8List(4);
  b[0] = (value >> 24) & 0xff;
  b[1] = (value >> 16) & 0xff;
  b[2] = (value >> 8) & 0xff;
  b[3] = value & 0xff;
  return b;
}

Uint8List arrayAppend(List<int> a, List<int> b) =>
    Uint8List.fromList([...a, ...b]);

Uint8List _randomBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

/// Zufälliger Exponent in [1, Q-1].
BigInt _randomExponent() {
  while (true) {
    final v = _bytesToBigInt(_randomBytes(_fieldSize)) % _qOrder;
    if (v != BigInt.zero) return v;
  }
}

// ─── EC-Punkt-Helfer ─────────────────────────────────────────────────────────
BigInt _px(ECPoint p) => p.x!.toBigInteger()!;
BigInt _py(ECPoint p) => p.y!.toBigInteger()!;

/// Punkt als rohe x||y-Bytes (2 * 32 = 64), wie `Packet` es serialisiert.
Uint8List _pointToXY(ECPoint p) =>
    arrayAppend(_bigIntToBytes(_px(p), _fieldSize),
        _bigIntToBytes(_py(p), _fieldSize));

ECPoint _pointFromXY(Uint8List x, Uint8List y) =>
    _curve.curve.createPoint(_bytesToBigInt(x), _bytesToBigInt(y));

/// Unkomprimierte Kodierung (0x04 || x || y, 65 Bytes) für den ZKP-Hash.
Uint8List _pointEncodedUncompressed(ECPoint p) => p.getEncoded(false);

bool _pointEquals(ECPoint a, ECPoint b) {
  final ea = _pointEncodedUncompressed(a);
  final eb = _pointEncodedUncompressed(b);
  if (ea.length != eb.length) return false;
  for (int i = 0; i < ea.length; i++) {
    if (ea[i] != eb[i]) return false;
  }
  return true;
}

// ─── Krypto-Primitiven ───────────────────────────────────────────────────────
Uint8List _sha256(Uint8List data) => SHA256Digest().process(data);

/// AES-128-ECB, ein 16-Byte-Block.
Uint8List _aesEcbBlock(Uint8List key, Uint8List input16) {
  final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(key));
  final out = Uint8List(16);
  cipher.processBlock(input16, 0, out, 0);
  return out;
}

// ─── Schlüsselpaar ───────────────────────────────────────────────────────────
class KeksKeyPair {
  final BigInt privateKey;
  final ECPoint publicKey;

  KeksKeyPair(this.privateKey, this.publicKey);

  /// Frisches zufälliges Schlüsselpaar auf secp256r1.
  factory KeksKeyPair.generate() {
    final d = _randomExponent();
    final pub = (_g * d)!;
    return KeksKeyPair(d, pub);
  }
}

// ─── Wire-Paket (J-PAKE-Runde) ───────────────────────────────────────────────
/// Serialisierung: point1.x|point1.y | point2.x|point2.y | hash  (je 32 Byte).
class KeksPacket {
  final BigInt hash;
  final ECPoint publicKeyPoint1;
  final ECPoint publicKeyPoint2;

  KeksPacket(this.hash, this.publicKeyPoint1, this.publicKeyPoint2);

  static KeksPacket? parse(Uint8List packet) {
    if (packet.length < _packetSize) return null;
    Uint8List slice(int i) =>
        Uint8List.sublistView(packet, i * _fieldSize, (i + 1) * _fieldSize);
    final point1 = _pointFromXY(slice(0), slice(1));
    final point2 = _pointFromXY(slice(2), slice(3));
    final hash = _bytesToBigInt(slice(4));
    return KeksPacket(hash, point1, point2);
  }

  Uint8List output() {
    final out = Uint8List(_packetSize);
    out.setRange(0, 64, _pointToXY(publicKeyPoint1));
    out.setRange(64, 128, _pointToXY(publicKeyPoint2));
    out.setRange(128, 160, _bigIntToBytes(hash, _fieldSize));
    return out;
  }
}

// ─── Zero-Knowledge-Proof (Schnorr) ──────────────────────────────────────────
BigInt _zeroKnowledgeHash(
    ECPoint g, ECPoint gv, ECPoint gx, Uint8List party) {
  final d = SHA256Digest();
  void upd(Uint8List bytes) {
    final len = _int32be(bytes.length);
    d.update(len, 0, len.length);
    d.update(bytes, 0, bytes.length);
  }

  upd(_pointEncodedUncompressed(g));
  upd(_pointEncodedUncompressed(gv));
  upd(_pointEncodedUncompressed(gx));
  upd(party);
  final out = Uint8List(32);
  d.doFinal(out, 0);
  return _bytesToBigInt(out) % _qOrder;
}

class _Zkp {
  final ECPoint g;
  final BigInt privateKey;
  final ECPoint publicKey;
  final Uint8List party;
  final BigInt _exponent = _randomExponent();
  ECPoint? _gv;

  _Zkp(this.g, this.privateKey, this.publicKey, this.party);

  ECPoint get gv => _gv ??= (g * _exponent)!;

  BigInt get proof =>
      (_exponent - _zeroKnowledgeHash(g, gv, publicKey, party) * privateKey) %
          _qOrder;
}

bool _validateZkp(ECPoint g, ECPoint publicKey, ECPoint gv, BigInt b,
    Uint8List party) {
  final hash = _zeroKnowledgeHash(g, gv, publicKey, party);
  final lhs = ((g * b)! + (publicKey * hash)!)!;
  return _pointEquals(lhs, gv);
}

// ─── J-PAKE-Kontext ──────────────────────────────────────────────────────────
class KeksContext {
  KeksKeyPair keyA = KeksKeyPair.generate();
  KeksKeyPair keyB = KeksKeyPair.generate();
  late Uint8List alice;
  late Uint8List bob;
  Uint8List? challenge;
  Uint8List? savedKey;
  // packet[1..3] = vom Sensor empfangene & validierte Runden-Pakete
  final List<KeksPacket?> packet = List.filled(4, null);
  int sequence = 0;

  final String password;
  Uint8List? _passwordBytes;

  KeksContext(this.password);

  Uint8List get passwordBytes {
    _passwordBytes ??= () {
      var pw = Uint8List.fromList(password.codeUnits);
      // Bei 6-stelligem Code wird "00" (0x30 0x30) vorangestellt.
      if (password.length == 6) {
        pw = arrayAppend(_kPrefix, pw);
      }
      return pw;
    }();
    return _passwordBytes!;
  }

  BigInt get passwordBigInteger => _bytesToBigInt(passwordBytes);

  KeksPacket? get round1Packet => packet[1];
  KeksPacket? get round2Packet => packet[2];
  KeksPacket? get round3Packet => packet[3];

  void reset() {
    savedKey = null;
    for (int i = 0; i < packet.length; i++) {
      packet[i] = null;
    }
  }

  void resetIfNotReady() {
    sequence = 0;
    if (savedKey == null && round3Packet == null) {
      reset();
    }
  }
}

// ─── J-PAKE-Berechnungen ─────────────────────────────────────────────────────
class KeksCalc {
  static KeksPacket _round12Packet(KeksContext ctx, bool part2) {
    final key = part2 ? ctx.keyB : ctx.keyA;
    final zkp = _Zkp(_g, key.privateKey, key.publicKey, ctx.alice);
    return KeksPacket(zkp.proof, key.publicKey, zkp.gv);
  }

  static KeksPacket round1Packet(KeksContext ctx) => _round12Packet(ctx, false);
  static KeksPacket round2Packet(KeksContext ctx) => _round12Packet(ctx, true);

  static bool _validateRound1(KeksPacket? p, Uint8List party) {
    if (p == null) return false;
    return _validateZkp(
        _g, p.publicKeyPoint1, p.publicKeyPoint2, p.hash, party);
  }

  static bool validateRound1(KeksContext ctx) =>
      _validateRound1(ctx.round1Packet, ctx.bob);
  static bool validateRound2(KeksContext ctx) =>
      _validateRound1(ctx.round2Packet, ctx.bob);

  static KeksPacket round3Packet(KeksContext ctx) {
    final p1 = ctx.round1Packet!;
    final p2 = ctx.round2Packet!;
    final x1 = ctx.keyA.publicKey;
    final x2 = ctx.keyB.privateKey;
    final x3 = p1.publicKeyPoint1;
    final x4 = p2.publicKeyPoint1;
    final s = ctx.passwordBigInteger;
    final x2s = (x2 * s) % _qOrder;
    final x134 = ((x1 + x3)! + x4)!;
    final a = (x134 * x2s)!;
    final zkp = _Zkp(x134, x2s, a, ctx.alice);
    return KeksPacket(zkp.proof, a, zkp.gv);
  }

  static bool validateRound3(KeksContext ctx) {
    final p = ctx.round3Packet;
    if (p == null) return false;
    final x1 = ctx.keyA.publicKey;
    final x2 = ctx.keyB.publicKey;
    final x3 = ctx.round1Packet!.publicKeyPoint1;
    final g = ((x1 + x2)! + x3)!;
    return _validateZkp(
        g, p.publicKeyPoint1, p.publicKeyPoint2, p.hash, ctx.bob);
  }

  static Uint8List? sharedKey(KeksContext ctx) {
    final p3 = ctx.round3Packet;
    if (p3 == null) return null;
    final point1 = p3.publicKeyPoint1;
    final x2 = ctx.keyB.privateKey;
    final x4 = ctx.round2Packet!.publicKeyPoint1;
    final s = ctx.passwordBigInteger;
    final key = ((point1 - (x4 * ((x2 * s) % _qOrder))!)! * x2)!;
    return _sha256(_bigIntToBytes(_px(key), _fieldSize));
  }

  static Uint8List? shortSharedKey(KeksContext ctx) {
    final full = sharedKey(ctx);
    if (full == null) return null;
    return Uint8List.sublistView(full, 0, 16);
  }

  /// AES-ECB(shortKey, challenge||challenge)[0:8].
  static Uint8List? calculateHash(KeksContext ctx) {
    final data = ctx.challenge;
    if (data == null) return null;
    final key = ctx.savedKey ?? shortSharedKey(ctx);
    if (key == null) return null;
    final doubleData = Uint8List(16);
    doubleData.setRange(0, data.length, data);
    doubleData.setRange(data.length, data.length * 2, data);
    final aes = _aesEcbBlock(key, doubleData);
    return Uint8List.sublistView(aes, 0, 8);
  }
}

// ─── Konfiguration (aus libkeks Config) ──────────────────────────────────────
final Uint8List _kAlice =
    Uint8List.fromList([0x36, 0xC6, 0x96, 0x56, 0xE6, 0x47]);
final Uint8List _kBob = Uint8List.fromList([0x37, 0x56, 0x27, 0x67, 0x56, 0x27]);
final Uint8List _kPrefix = Uint8List.fromList([0x30, 0x30]);
final Uint8List _kKeyCmd = Uint8List.fromList([0x0A]);
final Uint8List _kTimeExtended = Uint8List.fromList([0x06, 0x19]);
final Uint8List _kGetData = Uint8List.fromList([0x4E, 0x0A, 0xA9]);
final Uint8List _kGetData2 = Uint8List.fromList([0x4E]);

// Hinweis: _kAlice/_kBob sind die "party"-Marker aus libkeks (ALICE_B/BOB_B).
// In der Java-Quelle sind das die festen Hex-Strings "36C69656E647" / "375627675627".

/// "party"-Marker der App-Seite (libkeks ALICE).
Uint8List get aliceMarker => _kAlice;

/// "party"-Marker der Sensor-Seite (libkeks BOB).
Uint8List get bobMarker => _kBob;

// ─── Auth-Nachrichten (keks-Variante) ────────────────────────────────────────
class KeksAuthRequestTx {
  final Uint8List singleUseToken;
  final Uint8List bytes;

  KeksAuthRequestTx._(this.singleUseToken, this.bytes);

  factory KeksAuthRequestTx(
      {int tokenSize = 8, bool alt = false, Uint8List? chal}) {
    final token = _randomBytes(tokenSize);
    final slot = (alt ? 0x1 : 0x2) +
        ((chal != null && chal.length > 2) ? chal[2] : 0);
    final b = Uint8List(tokenSize + 2);
    b[0] = 0x02; // Opcode (keks: 0x02, NICHT das Legacy-0x01)
    b.setRange(1, 1 + tokenSize, token);
    b[tokenSize + 1] = slot & 0xff;
    return KeksAuthRequestTx._(token, b);
  }
}

class KeksAuthChallengeTx {
  final Uint8List bytes;
  KeksAuthChallengeTx(Uint8List challengeHash)
      : bytes = Uint8List.fromList([0x04, ...challengeHash]);
}

class KeksAuthStatusRx {
  final int authenticated;
  final int bonded;

  KeksAuthStatusRx._(this.authenticated, this.bonded);

  static KeksAuthStatusRx? parse(Uint8List packet) {
    if (packet.length < 3 || packet[0] != 0x05) return null;
    return KeksAuthStatusRx._(packet[1], packet[2]);
  }

  bool get isAuthenticated => authenticated == 1;
  bool get isBonded => bonded == 1;
  bool get needsRefresh => bonded == 3;
}

/// Wird geworfen, wenn der Sensor den (nicht portierten) Zertifikats-/QR-Pfad
/// für ein erstmaliges Pairing eines ungebondeten Sensors verlangt.
class KeksCertificateRequired implements Exception {
  final String message;
  KeksCertificateRequired(this.message);
  @override
  String toString() => 'KeksCertificateRequired: $message';
}

// ─── State-Machine (Port von libkeks Plugin.java) ─────────────────────────────
enum KeksState {
  init,
  unknown,
  roundStart,
  round1,
  round2,
  round3,
  pairing,
  bondFailure,
  requestAuth,
  challengeReply,
  getData,
  getData2,
}

/// Treibt den J-PAKE-Handshake. Die BLE-Schicht ruft [amConnected] bei
/// Verbindung, dann wiederholt [aNext] (liefert zu schreibende Nachrichten) und
/// leitet eingehende Notifications je nach [state] an [receivedData] (J-PAKE-
/// Runden) bzw. [receivedResponse] (Auth-Antworten) weiter.
///
/// Faithful port von xDrip+ `jamorham.keks.Plugin`. Der Zertifikats-/QR-Pfad
/// (SendCertificate*/SignChallenge) ist NICHT enthalten — er wird nur für das
/// erstmalige Pairing eines noch nicht gebondeten Sensors gebraucht und wirft
/// hier [KeksCertificateRequired].
class KeksPlugin {
  final KeksContext context;
  KeksState state = KeksState.init;
  Uint8List _accumulator = Uint8List(0);
  KeksAuthRequestTx? _lastAuthTx;

  KeksPlugin(String password)
      : context = KeksContext(password) {
    context.alice = aliceMarker;
    context.bob = bobMarker;
  }

  bool get isAuthenticated =>
      state == KeksState.getData || state == KeksState.getData2;

  void amConnected() {
    context.resetIfNotReady();
    state = KeksState.roundStart;
    _accumulator = Uint8List(0);
  }

  int _positionFromState() {
    switch (state) {
      case KeksState.round1:
        return 1;
      case KeksState.round2:
        return 2;
      case KeksState.round3:
        return 3;
      default:
        return 0;
    }
  }

  int _parameterFromState() {
    switch (state) {
      case KeksState.round1:
        return 0;
      case KeksState.round2:
        return 1;
      case KeksState.round3:
        return 2;
      default:
        return -1;
    }
  }

  int _expectedBytesForState() {
    switch (state) {
      case KeksState.round1:
      case KeksState.round2:
      case KeksState.round3:
        return _packetSize;
      default:
        return 0x602910; // praktisch "nie voll" für andere Zustände
    }
  }

  /// J-PAKE-Runden-Bytes (ggf. fragmentiert) sammeln. true, sobald ein
  /// vollständiges 160-Byte-Paket empfangen und validiert wurde.
  bool receivedData(Uint8List data) {
    _accumulator = arrayAppend(_accumulator, data);
    if (_accumulator.length < _expectedBytesForState()) return false;
    final pos = _positionFromState();
    context.packet[pos] = KeksPacket.parse(_accumulator);
    _accumulator = Uint8List(0);
    if (!_validate()) {
      context.packet[pos] = null;
      return false;
    }
    return true;
  }

  bool _validate() {
    if (context.packet[_positionFromState()] == null) return false;
    switch (state) {
      case KeksState.round1:
        return KeksCalc.validateRound1(context);
      case KeksState.round2:
        return KeksCalc.validateRound2(context);
      case KeksState.round3:
        return KeksCalc.validateRound3(context);
      default:
        return false;
    }
  }

  /// Auth-Antworten verarbeiten (Challenge-Verifikation, Auth-Status).
  bool receivedResponse(Uint8List data) {
    switch (state) {
      case KeksState.requestAuth:
        if (!_verifyChallenge(data)) {
          context.reset();
          if (context.sequence > 1) {
            throw const _MismatchWait();
          }
          return false;
        }
        context.challenge = Uint8List.sublistView(data, 9, 17);
        return true;

      case KeksState.challengeReply:
        final status = KeksAuthStatusRx.parse(data);
        if (status == null) return false;
        if (status.needsRefresh) context.reset();
        if (!status.isAuthenticated) {
          context.reset();
          state = status.isBonded ? KeksState.unknown : KeksState.bondFailure;
          return true;
        }
        if (status.isBonded) {
          state = context.passwordBytes.length > 4
              ? KeksState.getData
              : KeksState.getData2;
          return true;
        }
        // Authentifiziert, aber (noch) nicht gebondet -> Zertifikats-/QR-Pfad.
        throw KeksCertificateRequired(
            'Sensor verlangt erstmaliges Pairing (Zertifikat/QR) — nicht portiert');

      default:
        return false;
    }
  }

  bool _verifyChallenge(Uint8List data) {
    if (context.savedKey != null) return true;
    context.challenge = _lastAuthTx!.singleUseToken;
    final h = KeksCalc.calculateHash(context);
    if (h == null || data.length < 9) return false;
    for (int i = 0; i < 8; i++) {
      if (h[i] != data[i + 1]) return false;
    }
    return true;
  }

  KeksAuthRequestTx _authRequest() {
    _lastAuthTx = KeksAuthRequestTx(tokenSize: 8);
    return _lastAuthTx!;
  }

  List<Uint8List?> _sequencePacket(Uint8List? packet) {
    context.sequence++;
    final param = _parameterFromState();
    final command =
        param < 0 ? null : Uint8List.fromList([_kKeyCmd[0], param]);
    return [command, packet];
  }

  /// Nächste zu schreibende Nachrichten (Reihenfolge beibehalten; null = nichts).
  List<Uint8List?> aNext() {
    switch (state) {
      case KeksState.roundStart:
        if (context.round3Packet != null || context.savedKey != null) {
          state = KeksState.requestAuth;
          return [_authRequest().bytes, null];
        }
        state = KeksState.round1;
        return _sequencePacket(null);
      case KeksState.round1:
        state = KeksState.round2;
        return _sequencePacket(KeksCalc.round1Packet(context).output());
      case KeksState.round2:
        state = KeksState.round3;
        return _sequencePacket(KeksCalc.round2Packet(context).output());
      case KeksState.round3:
        state = KeksState.requestAuth;
        return [_authRequest().bytes, KeksCalc.round3Packet(context).output()];
      case KeksState.requestAuth:
        state = KeksState.challengeReply;
        return [KeksAuthChallengeTx(KeksCalc.calculateHash(context)!).bytes, null];
      case KeksState.challengeReply:
        state = KeksState.unknown;
        return [_kTimeExtended, null];
      case KeksState.pairing:
        state = KeksState.getData;
        return [_kTimeExtended, null];
      case KeksState.getData:
        state = KeksState.unknown;
        return [_kGetData];
      case KeksState.getData2:
        state = KeksState.unknown;
        return [_kGetData2];
      case KeksState.bondFailure:
        state = KeksState.unknown;
        return [_kGetData, null, null];
      default:
        return [];
    }
  }
}

class _MismatchWait implements Exception {
  const _MismatchWait();
  @override
  String toString() => 'Mismatch — wait';
}
