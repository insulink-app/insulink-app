/// Dexcom G7 authentication opcodes.
///
/// These byte values are REVERSE-ENGINEERED from the official app's
/// `com.dexcom.coresdk.transmitter.auth.AuthOpCodes` enum (the 3rd argument of
/// its `<init>(String, int ordinal, byte value)` constructor, recovered from
/// the decompiled smali). The opcode is the first byte written to the
/// Authentication characteristic; the remainder is the opcode payload.
///
/// Confidence: HIGH (extracted directly from the enum). The *sequence* and
/// payload layout below are inferred from the EC-JPAKE flow and should still be
/// confirmed against a real sensor capture.
enum G7AuthOpCode {
  txIdChallenge(0x01),
  appKeyChallenge(0x02),
  challengeReply(0x03),
  hashFromDisplay(0x04),
  statusReply(0x05),
  keepConnectionAlive(0x06),
  requestBond(0x07),
  requestBondResponse(0x08),
  exchangePakePayload(0x0A);

  const G7AuthOpCode(this.value);

  /// First byte on the wire.
  final int value;

  static G7AuthOpCode? fromByte(int b) {
    for (final op in G7AuthOpCode.values) {
      if (op.value == b) return op;
    }
    return null;
  }
}

/// The expected ordering of the handshake, inferred from the opcode names and
/// the EC-JPAKE structure. Used by the state machine to know what to send/await
/// next. CONFIRM against a real capture; reorder here if the sensor disagrees.
///
///  1. requestBond            → requestBondResponse
///  2. txIdChallenge          (serial-number based)
///  3. appKeyChallenge        → challengeReply
///  4. exchangePakePayload    (EC-JPAKE round 1, then round 2)
///  5. hashFromDisplay        (key-confirmation hash)
///  6. statusReply            (success → session established)
///  • keepConnectionAlive     (periodic, post-auth)
const List<G7AuthOpCode> kAuthHappyPath = [
  G7AuthOpCode.requestBond,
  G7AuthOpCode.txIdChallenge,
  G7AuthOpCode.appKeyChallenge,
  G7AuthOpCode.exchangePakePayload,
  G7AuthOpCode.hashFromDisplay,
  G7AuthOpCode.statusReply,
];
