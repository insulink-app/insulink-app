// Verifiziert die EC-J-PAKE-Mathematik des keks-Ports OHNE echten Sensor:
// zwei Parteien (App-Seite "A" und simulierter Sensor "B") führen den
// J-PAKE-Handshake gegeneinander aus und müssen denselben Sitzungsschlüssel
// ableiten. Das prüft Kurvenarithmetik, ZKP-Erzeugung/-Validierung,
// Paket-(De)Serialisierung, Schlüsseleinigung und die AES-Challenge.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/keks.dart';

void main() {
  test('J-PAKE: beide Parteien einigen sich auf denselben Schlüssel', () {
    const password = '2585';

    // Zwei symmetrische Kontexte. In der echten Welt ist B der Sensor; hier
    // simulieren wir ihn mit demselben Algorithmus (gleiches Passwort).
    final a = KeksContext(password)
      ..alice = aliceMarker
      ..bob = bobMarker;
    final b = KeksContext(password)
      // Aus B-Sicht sind die Rollen vertauscht: B ist "alice", A ist "bob".
      ..alice = bobMarker
      ..bob = aliceMarker;

    // Runde 1: jede Partei sendet ihr Round-1-Paket, die Gegenseite validiert.
    final aR1 = KeksCalc.round1Packet(a);
    final bR1 = KeksCalc.round1Packet(b);
    a.packet[1] = KeksPacket.parse(bR1.output());
    b.packet[1] = KeksPacket.parse(aR1.output());
    expect(KeksCalc.validateRound1(a), isTrue, reason: 'A validiert B-R1');
    expect(KeksCalc.validateRound1(b), isTrue, reason: 'B validiert A-R1');

    // Runde 2.
    final aR2 = KeksCalc.round2Packet(a);
    final bR2 = KeksCalc.round2Packet(b);
    a.packet[2] = KeksPacket.parse(bR2.output());
    b.packet[2] = KeksPacket.parse(aR2.output());
    expect(KeksCalc.validateRound2(a), isTrue, reason: 'A validiert B-R2');
    expect(KeksCalc.validateRound2(b), isTrue, reason: 'B validiert A-R2');

    // Runde 3.
    final aR3 = KeksCalc.round3Packet(a);
    final bR3 = KeksCalc.round3Packet(b);
    a.packet[3] = KeksPacket.parse(bR3.output());
    b.packet[3] = KeksPacket.parse(aR3.output());
    expect(KeksCalc.validateRound3(a), isTrue, reason: 'A validiert B-R3');
    expect(KeksCalc.validateRound3(b), isTrue, reason: 'B validiert A-R3');

    // Schlüsseleinigung: beide Seiten müssen denselben Sitzungsschlüssel haben.
    final keyA = KeksCalc.shortSharedKey(a);
    final keyB = KeksCalc.shortSharedKey(b);
    expect(keyA, isNotNull);
    expect(keyB, isNotNull);
    expect(keyA, equals(keyB),
        reason: 'Beide Parteien leiten denselben Sitzungsschlüssel ab');

    // Challenge-Antwort: A beantwortet eine 8-Byte-Challenge, B verifiziert sie
    // mit demselben Schlüssel — so läuft der echte AuthChallenge-Schritt.
    final challenge =
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    a.challenge = challenge;
    b.challenge = challenge;
    final hashA = KeksCalc.calculateHash(a);
    final hashB = KeksCalc.calculateHash(b);
    expect(hashA, isNotNull);
    expect(hashA, equals(hashB),
        reason: 'AES-Challenge-Antwort stimmt auf beiden Seiten überein');
  });

  test('Falsches Passwort -> kein gemeinsamer Schlüssel', () {
    final a = KeksContext('2585')
      ..alice = aliceMarker
      ..bob = bobMarker;
    final b = KeksContext('9999') // falscher Code
      ..alice = bobMarker
      ..bob = aliceMarker;

    a.packet[1] = KeksPacket.parse(KeksCalc.round1Packet(b).output());
    b.packet[1] = KeksPacket.parse(KeksCalc.round1Packet(a).output());
    a.packet[2] = KeksPacket.parse(KeksCalc.round2Packet(b).output());
    b.packet[2] = KeksPacket.parse(KeksCalc.round2Packet(a).output());
    a.packet[3] = KeksPacket.parse(KeksCalc.round3Packet(b).output());
    b.packet[3] = KeksPacket.parse(KeksCalc.round3Packet(a).output());

    expect(KeksCalc.shortSharedKey(a),
        isNot(equals(KeksCalc.shortSharedKey(b))),
        reason: 'Unterschiedliche Passwörter -> unterschiedliche Schlüssel');
  });
}
