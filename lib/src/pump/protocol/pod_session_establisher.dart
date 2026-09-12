import 'dart:math';
import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/milenage.dart';
import 'package:insulink/src/pump/protocol/pod_eap.dart';
import 'package:insulink/src/pump/protocol/pod_eap_bytes.dart';
import 'package:insulink/src/pump/protocol/pod_eap_resync.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

/// Establishes a session on top of an existing pairing, using EAP-AKA with the
/// long-term key in place of a SIM key.
///
/// The pod tracks the EAP sequence number and rejects anything it has already
/// seen. When that happens it returns its own counter and
/// [PodSessionResyncRequired] is thrown carrying it, so the caller can store the
/// corrected value and try once more — never a blind retry, which would fail
/// identically forever.
class PodSessionEstablisher {
  PodSessionEstablisher({
    required this.messageIo,
    required this.addresses,
    required this.longTermKey,
    required this.eapSequence,
    required this._messageSequence,
    Uint8List? controllerNonceHalf,
    Uint8List? challengeRandom,
    int? identifier,
  }) : _identifier = identifier ?? Random.secure().nextInt(256),
       _controllerNonceHalf =
           controllerNonceHalf ?? _randomBytes(_nonceHalfSize),
       _milenage = Milenage(
         key: longTermKey,
         sqn: encodeEapSequence(eapSequence),
         rand: challengeRandom ?? _randomBytes(16),
       );

  static const int _nonceHalfSize = 4;

  final PodMessageIo messageIo;
  final PodAddressPair addresses;
  final Uint8List longTermKey;
  final int eapSequence;
  final Uint8List _controllerNonceHalf;
  final Milenage _milenage;
  final int _identifier;

  int _messageSequence;

  Future<PodSessionKeys> establish() async {
    _messageSequence++;
    await messageIo.sendMessage(_challenge());

    final reply = await messageIo.receiveMessage();
    if (reply == null) {
      throw PodSessionException('Pod did not answer the session challenge');
    }
    final podNonceHalf = _readChallengeReply(
      PodEapMessage.parse(reply.payload),
    );

    _messageSequence++;
    await messageIo.sendMessage(_success());

    return PodSessionKeys(
      confidentialityKey: _milenage.ck,
      nonce: SessionNonce(
        prefix: Uint8List.fromList(_controllerNonceHalf + podNonceHalf),
        sequence: 0,
      ),
      messageSequence: _messageSequence,
      eapSequence: eapSequence,
    );
  }

  MessagePacket _challenge() {
    final message = PodEapMessage(
      code: PodEapCode.request,
      identifier: _identifier,
      attributes: [
        PodEapAttribute(PodEapAttributeType.autn, _milenage.autn),
        PodEapAttribute(PodEapAttributeType.rand, _milenage.rand),
        PodEapAttribute(PodEapAttributeType.customIv, _controllerNonceHalf),
      ],
    );
    return _wrap(message);
  }

  MessagePacket _success() {
    return _wrap(
      PodEapMessage(code: PodEapCode.success, identifier: _identifier),
    );
  }

  MessagePacket _wrap(PodEapMessage message) {
    return MessagePacket(
      type: PodMessageType.sessionEstablishment,
      source: addresses.myId,
      destination: addresses.podId,
      payload: message.toBytes(),
      sequenceNumber: _messageSequence,
    );
  }

  /// Checks the pod's answer and returns its half of the message nonce.
  Uint8List _readChallengeReply(PodEapMessage reply) {
    if (reply.identifier != _identifier) {
      throw PodSessionException('Session reply carries a different identifier');
    }
    PodEapResync(
      longTermKey: longTermKey,
      eapSequence: eapSequence,
      challengeRandom: _milenage.rand,
    ).throwIfNeeded(reply);

    if (reply.attributes.length != 2) {
      final onlyAttribute = reply.attributes.length == 1
          ? reply.attributes.single
          : null;
      if (onlyAttribute?.type == PodEapAttributeType.clientErrorCode) {
        throw PodSessionException(
          'Pod refused the challenge with a client error',
        );
      }
      throw PodSessionException(
        'Expected two session attributes, got ${reply.attributes.length}',
      );
    }

    Uint8List? podNonceHalf;
    for (final attribute in reply.attributes) {
      switch (attribute.type) {
        case PodEapAttributeType.res:
          if (!constantTimeEquals(attribute.payload, _milenage.res)) {
            throw PodSessionException('Pod failed the challenge — wrong key');
          }
        case PodEapAttributeType.customIv:
          podNonceHalf = attribute.payload.sublist(0, _nonceHalfSize);
        default:
          throw PodSessionException(
            'Unexpected session attribute ${attribute.type.name}',
          );
      }
    }
    if (podNonceHalf == null) {
      throw PodSessionException('Pod sent no nonce half');
    }
    return podNonceHalf;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
