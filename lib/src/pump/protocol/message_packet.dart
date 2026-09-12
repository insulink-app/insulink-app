import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_ids.dart';

/// What a [MessagePacket] carries, encoded into the low nibble of the second
/// flag byte.
enum PodMessageType {
  clear(0),
  encrypted(1),
  sessionEstablishment(2),
  pairing(3);

  const PodMessageType(this.value);

  final int value;

  static PodMessageType byValue(int value) {
    return PodMessageType.values.firstWhere(
      (candidate) => candidate.value == value,
      orElse: () => throw PodMessageException('Unknown message type: $value'),
    );
  }
}

/// Raised when a frame off the wire cannot be read as a message.
class PodMessageException implements Exception {
  PodMessageException(this.message);

  final String message;

  @override
  String toString() => 'PodMessageException: $message';
}

/// The 16-byte header plus payload that wraps everything the pod exchanges,
/// at every stage: pairing, session establishment and encrypted commands.
///
/// The header doubles as the additional authenticated data for the AES-CCM
/// layer, which is why [toBytes] takes [forEncryption]: an encrypted packet's
/// length field counts the payload WITHOUT the 8-byte tag once the tag is
/// present, but counts the plaintext length while the tag is being computed.
class MessagePacket {
  MessagePacket({
    required this.type,
    required this.source,
    required this.destination,
    required this.payload,
    required this.sequenceNumber,
    this.ack = false,
    this.ackNumber = 0,
    this.eqos = 0,
    this.priority = false,
    this.lastMessage = false,
    this.gateway = false,
    this.sas = true,
    this.tfs = false,
    this.version = 0,
  });

  static const int headerSize = 16;
  static const List<int> _magic = [0x54, 0x57]; // "TW"

  final PodMessageType type;
  final PodId source;
  final PodId destination;
  final Uint8List payload;
  final int sequenceNumber;
  final bool ack;
  final int ackNumber;
  final int eqos;
  final bool priority;
  final bool lastMessage;
  final bool gateway;
  final bool sas;
  final bool tfs;
  final int version;

  MessagePacket withPayload(Uint8List replacement) {
    return MessagePacket(
      type: type,
      source: source,
      destination: destination,
      payload: replacement,
      sequenceNumber: sequenceNumber,
      ack: ack,
      ackNumber: ackNumber,
      eqos: eqos,
      priority: priority,
      lastMessage: lastMessage,
      gateway: gateway,
      sas: sas,
      tfs: tfs,
      version: version,
    );
  }

  /// Serializes header + payload. Bit positions are counted from the MOST
  /// significant bit, matching the pod's own numbering.
  Uint8List toBytes({bool forEncryption = false}) {
    final out = Uint8List(headerSize + payload.length);
    out.setRange(0, 2, _magic);

    var flagsOne = 0;
    flagsOne |= _bit(0, version & 4 != 0);
    flagsOne |= _bit(1, version & 2 != 0);
    flagsOne |= _bit(2, version & 1 != 0);
    flagsOne |= _bit(3, sas);
    flagsOne |= _bit(4, tfs);
    flagsOne |= _bit(5, eqos & 4 != 0);
    flagsOne |= _bit(6, eqos & 2 != 0);
    flagsOne |= _bit(7, eqos & 1 != 0);

    var flagsTwo = 0;
    flagsTwo |= _bit(0, ack);
    flagsTwo |= _bit(1, priority);
    flagsTwo |= _bit(2, lastMessage);
    flagsTwo |= _bit(3, gateway);
    flagsTwo |= _bit(4, type.value & 8 != 0);
    flagsTwo |= _bit(5, type.value & 4 != 0);
    flagsTwo |= _bit(6, type.value & 2 != 0);
    flagsTwo |= _bit(7, type.value & 1 != 0);

    out[2] = flagsOne;
    out[3] = flagsTwo;
    out[4] = sequenceNumber & 0xFF;
    out[5] = ackNumber & 0xFF;

    final carriesTag = type == PodMessageType.encrypted && !forEncryption;
    final size = payload.length - (carriesTag ? _tagSize : 0);
    out[6] = (size >> 3) & 0xFF;
    out[7] = (size << 5) & 0xFF;

    out.setRange(8, 12, source.address);
    out.setRange(12, 16, destination.address);
    out.setRange(16, out.length, payload);
    return out;
  }

  static int _bit(int index, bool set) {
    return set ? 1 << (7 - index) : 0;
  }

  static const int _tagSize = 8;

  static MessagePacket parse(Uint8List frame) {
    if (frame.length < headerSize) {
      throw PodMessageException('Frame shorter than header: ${frame.length}');
    }
    if (frame[0] != _magic[0] || frame[1] != _magic[1]) {
      throw PodMessageException('Missing TW magic');
    }
    final flagsOne = frame[2];
    final flagsTwo = frame[3];
    final version =
        (_get(flagsOne, 0) << 2) | (_get(flagsOne, 1) << 1) | _get(flagsOne, 2);
    if (version != 0) {
      throw PodMessageException('Unsupported message version: $version');
    }
    final type = PodMessageType.byValue(
      (_get(flagsTwo, 7)) |
          (_get(flagsTwo, 6) << 1) |
          (_get(flagsTwo, 5) << 2) |
          (_get(flagsTwo, 4) << 3),
    );
    final size = (frame[6] << 3) | (frame[7] >> 5);
    final end =
        headerSize + size + (type == PodMessageType.encrypted ? _tagSize : 0);
    if (frame.length < end) {
      throw PodMessageException(
        'Frame truncated: need $end, got ${frame.length}',
      );
    }
    return MessagePacket(
      type: type,
      source: PodId(Uint8List.fromList(frame.sublist(8, 12))),
      destination: PodId(Uint8List.fromList(frame.sublist(12, 16))),
      payload: Uint8List.fromList(frame.sublist(headerSize, end)),
      sequenceNumber: frame[4],
      ack: _get(flagsTwo, 0) != 0,
      ackNumber: frame[5],
      eqos:
          _get(flagsOne, 7) |
          (_get(flagsOne, 6) << 1) |
          (_get(flagsOne, 5) << 2),
      priority: _get(flagsTwo, 1) != 0,
      lastMessage: _get(flagsTwo, 2) != 0,
      gateway: _get(flagsTwo, 3) != 0,
      sas: _get(flagsOne, 3) != 0,
      tfs: _get(flagsOne, 4) != 0,
      version: version,
    );
  }

  static int _get(int flags, int index) {
    return flags & (1 << (7 - index)) != 0 ? 1 : 0;
  }
}
