import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:pointycastle/export.dart';

/// The per-message nonce for the AES-CCM layer.
///
/// The 8-byte prefix is fixed for the session (both sides contribute half of it
/// during the EAP handshake); the trailing 5 bytes are a counter that steps on
/// every message. The counter's top bit encodes direction, so the two sides
/// never reuse a nonce with the same key even though they share the counter
/// space — reuse would break the confidentiality of the whole session.
class SessionNonce {
  SessionNonce({required this.prefix, required this.sequence})
      : assert(prefix.length == 8);

  final Uint8List prefix;
  int sequence;

  Uint8List next({required bool podIsReceiver}) {
    sequence++;
    final counter = Uint8List(5);
    var remaining = sequence;
    for (var index = 4; index >= 0; index--) {
      counter[index] = remaining & 0xFF;
      remaining >>= 8;
    }
    counter[0] = podIsReceiver ? counter[0] & 0x7F : counter[0] | 0x80;
    return Uint8List.fromList(prefix + counter);
  }
}

/// Raised when a received message fails its authentication tag.
class PodDecryptException implements Exception {
  PodDecryptException(this.message);

  final String message;

  @override
  String toString() => 'PodDecryptException: $message';
}

/// AES-CCM with a 64-bit tag over every command and response once the session
/// is up, authenticating the 16-byte message header as associated data so a
/// replayed or re-addressed packet does not verify.
class SessionCipher {
  SessionCipher({required this.nonce, required this.confidentialityKey})
      : assert(confidentialityKey.length == 16);

  static const int tagSize = 8;

  final SessionNonce nonce;
  final Uint8List confidentialityKey;

  MessagePacket encrypt(MessagePacket message) {
    final header = message.toBytes(forEncryption: true).sublist(0, MessagePacket.headerSize);
    final sealed = _run(
      forEncryption: true,
      nonce: nonce.next(podIsReceiver: true),
      header: header,
      input: message.payload,
    );
    return message.withPayload(sealed);
  }

  MessagePacket decrypt(MessagePacket message) {
    if (message.payload.length < tagSize) {
      throw PodDecryptException('Encrypted payload shorter than its tag');
    }
    final header = message.toBytes().sublist(0, MessagePacket.headerSize);
    try {
      final opened = _run(
        forEncryption: false,
        nonce: nonce.next(podIsReceiver: false),
        header: header,
        input: message.payload,
      );
      return message.withPayload(opened);
    } on InvalidCipherTextException catch (error) {
      throw PodDecryptException('Authentication tag mismatch: ${error.message}');
    } on StateError catch (error) {
      // PointyCastle reports a failed CCM tag as a StateError, not as an
      // InvalidCipherTextException. Both have to land on the same path: an
      // unauthenticated payload must never reach the response parser.
      throw PodDecryptException('Authentication tag mismatch: ${error.message}');
    }
  }

  Uint8List _run({
    required bool forEncryption,
    required Uint8List nonce,
    required Uint8List header,
    required Uint8List input,
  }) {
    final cipher = CCMBlockCipher(AESEngine())
      ..init(
        forEncryption,
        AEADParameters(KeyParameter(confidentialityKey), tagSize * 8, nonce, header),
      );
    final out = Uint8List(cipher.getOutputSize(input.length));
    final written = cipher.processBytes(input, 0, input.length, out, 0);
    final finished = cipher.doFinal(out, written);
    return Uint8List.sublistView(out, 0, written + finished);
  }
}
