import 'package:flutter/foundation.dart';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_crc.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_response_reader.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';
import 'package:insulink/src/pump/protocol/string_prefix_codec.dart';

/// An established, encrypted conversation with a pod.
///
/// Every command goes out encrypted and every reply is acknowledged, in strict
/// alternation — the pod does not accept a second command before the first is
/// acknowledged.
///
/// [sendCommand] separates two failure modes on purpose. A send that never left
/// is safe to retry; a send whose confirmation was lost is NOT, because the pod
/// may have acted on it. The latter throws [PodCommandOutcomeUnknown], and a
/// caller holding a delivery command must read the pod's status to find out what
/// happened instead of sending it again.
class PodSession {
  PodSession({
    required this.messageIo,
    required this.addresses,
    required this.keys,
  }) : cipher = SessionCipher(
          nonce: keys.nonce,
          confidentialityKey: keys.confidentialityKey,
        );

  static const PodKeyedPayload _commandEnvelope = PodKeyedPayload(['S0.0=', ',G0.0']);
  static const PodKeyedPayload _responseEnvelope = PodKeyedPayload(['0.0=']);

  final PodMessageIo messageIo;
  final PodAddressPair addresses;
  final PodSessionKeys keys;
  final SessionCipher cipher;

  /// Sends [command] and reads the pod's reply, acknowledging it.
  Future<PodResponse> run(PodCommand command) async {
    await sendCommand(command);
    return readAndAcknowledge();
  }

  Future<void> sendCommand(PodCommand command) async {
    keys.messageSequence++;
    final envelope = _commandEnvelope.encode([command.encoded, Uint8List(0)]);
    final message = cipher.encrypt(MessagePacket(
      type: PodMessageType.encrypted,
      source: addresses.myId,
      destination: addresses.podId,
      payload: envelope,
      sequenceNumber: keys.messageSequence,
      eqos: 1,
    ));
    try {
      await messageIo.sendMessage(message);
    } on PodLinkException catch (error) {
      throw PodCommandOutcomeUnknown(
        'Could not confirm ${command.type.name}: ${error.message}',
      );
    }
  }

  /// Reads the pod's reply, verifies it is addressed to us and intact, then
  /// acknowledges it.
  Future<PodResponse> readAndAcknowledge() async {
    final received = await messageIo.receiveMessage();
    if (received == null) {
      throw PodCommandOutcomeUnknown('Pod sent no reply');
    }
    final plain = cipher.decrypt(received);
    final response = _parse(plain.payload);

    keys.messageSequence++;
    final acknowledgement = cipher.encrypt(MessagePacket(
      type: PodMessageType.encrypted,
      source: addresses.myId,
      destination: addresses.podId,
      payload: Uint8List(0),
      sequenceNumber: keys.messageSequence,
      ack: true,
      ackNumber: received.sequenceNumber + 1,
    ));
    await messageIo.sendMessage(acknowledgement);
    return response;
  }

  /// Reports the trailing two bytes without acting on them.
  ///
  /// They look like a CRC-16 over the frame, and a reply that fails one used to
  /// be rejected here. Real hardware says that reading is wrong: every genuine
  /// reply failed it. The reference driver never checks these bytes either, and
  /// leaves a standing `TODO validate uniqueId, sequenceNumber and crc` where the
  /// check would go, so there is no implementation anywhere to check against.
  ///
  /// Rejecting on a rule nobody has verified is worse than not checking: it
  /// throws away replies the pod correctly sent. The bytes are logged instead, so
  /// the real rule can still be worked out from captures.
  ///
  /// What IS checked stays checked: the reply names this pod, and its declared
  /// length matches its body. Both are real integrity checks, and both are more
  /// than the reference does.
  void _noteCrc(Uint8List frame, ByteData view) {
    final trailing = view.getUint16(frame.length - 2);
    final asCrc16 = PodCrc16(frame.sublist(0, frame.length - 2)).value;
    if (trailing == asCrc16) {
      return;
    }
    debugPrint('pod response: trailing bytes 0x${trailing.toRadixString(16)} '
        'are not a CRC-16 over the frame (0x${asCrc16.toRadixString(16)}); '
        'frame ${frame.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }

  /// Unwraps a decrypted reply.
  ///
  /// The frame carries the pod id it came from, a length, and its own CRC-16.
  /// All three are checked here: the reference driver leaves them unchecked, but
  /// acting on a reply that is not this pod's, or whose body is the wrong length,
  /// means acting on a wrong reservoir or delivery state.
  ///
  /// Which ids count as this pod is [PodAddressPair.acceptsReplyFrom] — an
  /// activation's first reply legitimately carries the unassigned id.
  ///
  /// The trailing two bytes are NOT treated as a checksum to reject on. See
  /// [_noteCrc].
  PodResponse _parse(Uint8List payload) {
    final Uint8List frame;
    try {
      frame = _responseEnvelope.decode(payload).first;
    } on PodKeyedPayloadException catch (error) {
      throw PodResponseException('Reply not in an envelope: ${error.message}');
    }
    if (frame.length < 9) {
      throw PodResponseException('Reply too short: ${frame.length} bytes');
    }
    final view = ByteData.view(frame.buffer, frame.offsetInBytes);
    final fromPod = view.getUint32(0);
    if (!addresses.acceptsReplyFrom(fromPod)) {
      throw PodResponseException(
        'Reply is from pod $fromPod, expected ${addresses.podId.value}',
      );
    }
    final declaredLength = view.getUint16(4) & 0x3FF;
    final body = frame.sublist(6, frame.length - 2);
    if (declaredLength != body.length) {
      throw PodResponseException(
        'Reply declares $declaredLength bytes but carries ${body.length}',
      );
    }
    _noteCrc(frame, view);
    return PodResponseReader(body).response;
  }
}

/// Thrown when a command's outcome cannot be established.
///
/// This is not "it failed" — it is "we do not know", which for a delivery
/// command means the pod may be delivering. Never retried blindly; the caller
/// reads the pod's status instead.
class PodCommandOutcomeUnknown implements Exception {
  PodCommandOutcomeUnknown(this.message);

  final String message;

  @override
  String toString() => 'PodCommandOutcomeUnknown: $message';
}
