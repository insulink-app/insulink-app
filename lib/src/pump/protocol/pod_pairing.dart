import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/key_exchange.dart';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/string_prefix_codec.dart';

/// What a completed pairing yields: the pod's long-term key and the message
/// sequence number the first session must continue from.
class PodPairingResult {
  const PodPairingResult({required this.longTermKey, required this.messageSequence});

  final Uint8List longTermKey;
  final int messageSequence;
}

/// Negotiates the long-term key with a pod that has not been paired yet.
///
/// Four exchanges over the pairing message type: we name the pod id we intend to
/// use, both sides trade a public key and nonce, both send the confirmation
/// value the other can recompute, and a final handshake closes it.
///
/// Where this can be abandoned matters, and the boundary is earlier than it looks.
/// The pod may keep the key from the moment OUR confirmation reaches it — not from
/// when its own confirmation reaches us. So the key is handed to [onKeyDerived] and
/// stored before that message goes out. Only a [PodPairingMismatch] proves the key
/// is worthless; every other failure leaves it possibly good and therefore worth
/// keeping.
class PodPairing {
  PodPairing({
    required this.messageIo,
    required this.addresses,
    required this.onKeyDerived,
    PodKeyExchange? keyExchange,
  }) : keyExchange = keyExchange ?? PodKeyExchange.generate();

  /// A serialised get-status command, which the pod expects as the second field
  /// of the opening pairing message.
  static const List<int> _openingStatusRequest = [
    0xff, 0xc3, 0x2d, 0xbd, 0x08, 0x03, 0x0e, 0x01, 0x00, 0x00, 0x8a,
  ];

  static const PodKeyedPayload _opening = PodKeyedPayload(['SP1=', ',SP2=']);
  static const PodKeyedPayload _controllerOffer = PodKeyedPayload(['SPS1=']);
  static const PodKeyedPayload _confirmation = PodKeyedPayload(['SPS2=']);
  static const PodKeyedPayload _finish = PodKeyedPayload(['SP0,GP0']);
  static const PodKeyedPayload _finishReply = PodKeyedPayload(['P0=']);

  final PodMessageIo messageIo;
  final PodAddressPair addresses;
  final PodKeyExchange keyExchange;

  /// Hands the derived key out the instant it exists, BEFORE our confirmation is
  /// sent — because the pod may keep the key the moment that confirmation lands,
  /// and from then on a pod we cannot address is a pod nobody can ever use again.
  ///
  /// Awaited, so the key is durably stored before anything else is attempted.
  final Future<void> Function(Uint8List longTermKey) onKeyDerived;

  int _sequence = 1;

  Future<PodPairingResult> negotiate() async {
    await _send(_opening.encode([
      addresses.podId.address,
      Uint8List.fromList(_openingStatusRequest),
    ]));
    _sequence++;
    await _send(_controllerOffer.encode([keyExchange.offer]));
    keyExchange.acceptPodOffer(_expect(_controllerOffer, await _receive('pod key offer')));

    // The key exists now. Store it before sending our confirmation: the pod may
    // keep it the moment that message lands, and everything after this point can
    // fail on a dropped link. A key kept but unverified can be discarded later; a
    // key never stored cannot be recovered at all.
    await onKeyDerived(keyExchange.longTermKey);

    _sequence++;
    await _send(_confirmation.encode([keyExchange.controllerConfirmation]));
    keyExchange.verifyPodConfirmation(
      _expect(_confirmation, await _receive('pod confirmation')),
    );

    _sequence++;
    await _closeQuietly();

    return PodPairingResult(
      longTermKey: keyExchange.longTermKey,
      messageSequence: _sequence,
    );
  }

  /// Sends the closing handshake and reads its reply without letting a failure
  /// discard a key the pod has already stored.
  Future<void> _closeQuietly() async {
    try {
      await _send(_finish.encode([Uint8List(0)]));
      final reply = await messageIo.receiveMessage();
      if (reply != null) {
        _finishReply.decode(reply.payload);
      }
    } on Exception {
      return;
    }
  }

  Future<void> _send(Uint8List payload) {
    return messageIo.sendMessage(MessagePacket(
      type: PodMessageType.pairing,
      source: addresses.myId,
      // The not-activated broadcast id, verified against AndroidAPS master:
      // LTKExchanger sends every pairing message to Ids.notActivated()
      // (0xFFFFFFFE), while the id the pod will be GIVEN travels only inside
      // SP1's payload. An earlier "fix" here to the assigned id was wrong.
      destination: PodId.notActivated,
      payload: payload,
      sequenceNumber: _sequence,
    ));
  }

  Future<MessagePacket> _receive(String what) async {
    final message = await messageIo.receiveMessage();
    if (message == null) {
      throw PodPairingException('No $what received');
    }
    return message;
  }

  Uint8List _expect(PodKeyedPayload codec, MessagePacket message) {
    try {
      return codec.decode(message.payload).first;
    } on PodKeyedPayloadException catch (error) {
      throw PodPairingException('Malformed pairing reply: ${error.message}');
    }
  }
}
