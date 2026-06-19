import 'dart:async';
import 'dart:typed_data';

import '../rust/api/jpake.dart';
import 'ble_transport.dart';
import 'display_certs.dart';
import 'opcodes.dart';

/// Thrown when the handshake fails in a way that is typically transient — a lost
/// or misaligned BLE notification on the J-PAKE channel (3538 uses unacknowledged
/// notifications) corrupts a round payload, so the derived session key is wrong
/// and key-confirmation mismatches. The caller should retry on a fresh GATT link
/// rather than surface it to the user.
class G7HandshakeException implements Exception {
  G7HandshakeException(this.message);
  final String message;
  @override
  String toString() => 'G7HandshakeException: $message';
}

/// Drives the full G7 authentication handshake, faithful to Juggluco's
/// DexGattCallback flow. The EC-JPAKE crypto is the Rust [G7Jpake] core
/// (byte-validated against Juggluco's reference vectors).
///
/// Sequence (fresh pairing):
///   1. EC-JPAKE rounds 0/1/2 — index byte `{0x0A, n}` on the auth char (3535),
///      160-byte round payloads on the J-PAKE char (3538).
///   2. AES key confirmation: 0x02(write) → 0x03(notify) → 0x04(write) → 0x05.
///   3. Bonding: 0x06/0x07 → 0x08 → OS createBond.
///
/// Still TODO (the known open gap): the 0x0B certificate exchange and 0x0C
/// proof-of-possession that some firmware requires between steps 2 and 3.
class G7AuthSession {
  G7AuthSession({
    required this.transport,
    required this.pairingCode,
    this.log = print,
    this.stepTimeout = const Duration(seconds: 12),
  });

  final BleTransport transport;

  /// The sensor pairing code (applicator). Used as the EC-JPAKE password.
  final String pairingCode;

  final void Function(String) log;
  final Duration stepTimeout;

  late final G7Jpake _jpake = G7Jpake(pairingCode: pairingCode);

  Uint8List _frame(G7AuthOpCode op, [List<int> extra = const []]) =>
      Uint8List.fromList([op.value, ...extra]);

  Future<Uint8List> _awaitAuth(G7AuthOpCode op) async {
    final m = await transport.authStream
        .map((e) => Uint8List.fromList(e))
        .firstWhere((m) => m.isNotEmpty && m.first == op.value)
        .timeout(stepTimeout);
    log('<- ${op.name}: ${_hex(m)}');
    return m;
  }

  Future<void> _sendAuth(G7AuthOpCode op, [List<int> extra = const []]) async {
    final f = _frame(op, extra);
    log('-> ${op.name}: ${_hex(f)}');
    await transport.writeAuth(f);
  }

  /// Send `{0x0A, idx}` on the auth char and receive the sensor's 160-byte round
  /// payload from 3538. The read listener is attached BEFORE the write to avoid a
  /// race, and we do NOT send our own payload here — the sensor must send first.
  Future<Uint8List> _recvRound(int idx) async {
    await _sendAuth(G7AuthOpCode.exchangePakePayload, [idx]);
    final received = await transport.takeJpake(160, timeout: stepTimeout);
    log('<- jpake round $idx (${received.length} B): ${_hexHead(received)}');
    return received;
  }

  /// Execute the handshake. Returns the 16-byte session key on success.
  Future<Uint8List> run() async {
    // Start from a clean J-PAKE buffer so stray bytes from a previous (failed)
    // attempt can't misalign the 160-byte round payloads.
    transport.clearJpakeBuffer();

    // --- EC-JPAKE rounds ---------------------------------------------------
    // Per the real trace, each phase is: write {0x0A,n}; the SENSOR sends its
    // 160-byte cert first; THEN we send ours. (Sending early made it disconnect.)
    // NOTE: the G7's round ZKP routinely does NOT verify under our raw-point wire
    // framing, yet the handshake still completes — so we log and continue, exactly
    // as Juggluco does. Do NOT turn this into a hard error: aborting here drops the
    // link before we send our payload, and the G7 then rejects the immediate
    // reconnect (REMOTE_USER_TERMINATED / CONNECTION_TIMEOUT).
    final g3 = await _recvRound(0);
    if (!_jpake.setSensorRound1(payload: g3)) {
      log('note: sensor round-0 ZKP unverified (continuing, as Juggluco does)');
    }
    await transport.writeJpake(_jpake.round1Payload());

    final g4 = await _recvRound(1);
    if (!_jpake.setSensorRound2(payload: g4)) {
      log('note: sensor round-1 ZKP unverified (continuing)');
    }
    await transport.writeJpake(_jpake.round2Payload());

    final sensorB = await _recvRound(2);
    await transport.writeJpake(_jpake.round3Payload());
    final sessionKey = _jpake.setSensorRound3(payload: sensorB);
    log('derived session key: ${_hex(sessionKey)}');

    // AES key confirmation, signing with the freshly-derived J-PAKE key.
    final reconnect = await _aesConfirm((d) => _jpake.aes8(data8: d));

    // --- Fresh pair: display-certificate exchange + proof-of-possession ----
    if (!reconnect) {
      await _certExchange();
      await _proofOfPossession();
      await _bond();
    }

    return sessionKey;
  }

  /// Reconnect path: skip J-PAKE/cert/PoP and re-authenticate with a stored
  /// session key. Returns the same key on success. Throws if the sensor rejects
  /// it (caller should then fall back to [run]).
  Future<Uint8List> runReconnect(Uint8List sessionKey) async {
    log('reconnecting with stored session key…');
    final reconnect = await _aesConfirm(
      (d) => aes8WithKey(sessionKey: sessionKey, data8: d),
    );
    if (!reconnect) {
      // Sensor wants a fresh pair despite our stored key.
      throw StateError('sensor requires re-pairing (not in reconnect state)');
    }
    return sessionKey;
  }

  /// Shared AES key-confirmation (opcodes 0x02→0x03→0x04→0x05). [aes8] signs an
  /// 8-byte block with the session key (J-PAKE-derived or stored). Returns true
  /// if the sensor reports the reconnect/bonded state (`05 01 01`).
  Future<bool> _aesConfirm(Uint8List Function(Uint8List) aes8) async {
    final nonce = _randomBytes(8);
    // Attach the reply listener BEFORE writing — the sensor answers instantly
    // and a broadcast stream won't replay a notification we weren't listening for.
    final replyFut = _awaitAuth(G7AuthOpCode.challengeReply);
    await _sendAuth(G7AuthOpCode.appKeyChallenge, [...nonce, 0x02]);

    final reply = await replyFut;
    final expect = aes8(Uint8List.fromList(nonce));
    final got = reply.sublist(1, 9);
    if (!_listEq(expect, got)) {
      throw G7HandshakeException(
        'sensor key-confirmation mismatch: expected ${_hex(expect)}, got ${_hex(got)}',
      );
    }
    final challenge = Uint8List.fromList(reply.sublist(9, 17));
    final statusFut = _awaitAuth(G7AuthOpCode.statusReply);
    await _sendAuth(G7AuthOpCode.hashFromDisplay, aes8(challenge));

    final status = await statusFut;
    if (status.length < 2 || status[1] != 0x01) {
      throw StateError('G7 auth failed, statusReply=${_hex(status)}');
    }
    final reconnect = status.length > 2 && status[2] == 0x01;
    log(
      'authenticated (${reconnect ? "reconnect" : "fresh pair (cert exchange required)"})',
    );
    return reconnect;
  }

  static const _opCert = 0x0B;
  static const _opPop = 0x0C;

  /// 0x0B: for each display cert, write `{0x0B, idx, len32}`, read the sensor's
  /// 7-byte size header + its cert on 3538, then send our cert on 3538.
  Future<void> _certExchange() async {
    for (var idx = 0; idx < kDisplayCerts.length; idx++) {
      final our = kDisplayCerts[idx];
      final sizeHdr = transport.authStream
          .map((e) => Uint8List.fromList(e))
          .firstWhere((m) => m.isNotEmpty && m.first == _opCert)
          .timeout(stepTimeout);
      final len = our.length;
      await transport.writeAuth([
        _opCert,
        idx,
        len & 0xFF,
        (len >> 8) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 24) & 0xFF,
      ]);
      final hdr = await sizeHdr; // {0x0B,0x00,which,size_LE16,...}
      final sensorSize = hdr.length >= 5 ? hdr[3] | (hdr[4] << 8) : 0;
      log('cert$idx: sensor size=$sensorSize, sending ${our.length}B');
      if (sensorSize > 0) {
        final sensorCert = await transport.takeJpake(
          sensorSize,
          timeout: stepTimeout,
        );
        log('cert$idx: received sensor cert (${sensorCert.length}B)');
      }
      await transport.writeJpake(our);
    }
  }

  /// 0x0C: send our PoP challenge; sign the sensor's challenge with the embedded
  /// display key and return it on 3538.
  Future<void> _proofOfPossession() async {
    final theirChallenge = transport.authStream
        .map((e) => Uint8List.fromList(e))
        .firstWhere((m) => m.isNotEmpty && m.first == _opPop)
        .timeout(stepTimeout);
    await transport.writeAuth([_opPop, ..._randomBytes(16)]);
    final challenge = await theirChallenge; // 0x0C ‖ 16 bytes
    final sig = _jpake.popSign(challenge: challenge); // 64-byte r‖s
    log('PoP: signing sensor challenge, returning 64B signature');
    await transport.writeJpake(sig);
    await transport.writeAuth([0x0D, 0x00, 0x02]);
  }

  /// Bonding: proceed byte, then let Android create the BLE bond.
  Future<void> _bond() async {
    await _sendAuth(G7AuthOpCode.keepConnectionAlive, [0x19]);
    log('requesting OS bond…');
    await transport.createBond();
  }

  void dispose() => _jpake.dispose();

  static List<int> _randomBytes(int n) {
    // Non-crypto nonce is fine here; the security is in the J-PAKE secret.
    final now = DateTime.now().microsecondsSinceEpoch;
    return List<int>.generate(n, (i) => (now >> (i * 8)) & 0xFF ^ (i * 31));
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

  String _hexHead(List<int> b) {
    final head = b.length > 12 ? b.sublist(0, 12) : b;
    return '${_hex(head)}…';
  }
}
