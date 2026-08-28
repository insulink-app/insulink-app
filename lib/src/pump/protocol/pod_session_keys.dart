import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/session_cipher.dart';

/// Raised when a session cannot be established.
class PodSessionException implements Exception {
  PodSessionException(this.message);

  final String message;

  @override
  String toString() => 'PodSessionException: $message';
}

/// A freshly negotiated session: the key every later message is encrypted with,
/// the nonce both sides contributed to, and where the message counter stands.
class PodSessionKeys {
  PodSessionKeys({
    required this.confidentialityKey,
    required this.nonce,
    required this.messageSequence,
    required this.eapSequence,
  });

  final Uint8List confidentialityKey;
  final SessionNonce nonce;
  int messageSequence;

  /// The EAP sequence number this session used. It must be persisted and
  /// incremented for the next one — reusing it makes the pod refuse the
  /// handshake and demand a resynchronisation.
  final int eapSequence;
}

/// Thrown when the pod rejects our EAP sequence number and offers its own.
///
/// The caller must persist [synchronizedEapSequence] before retrying, or the
/// next attempt fails the same way.
class PodSessionResyncRequired implements Exception {
  PodSessionResyncRequired(this.synchronizedEapSequence);

  final int synchronizedEapSequence;

  @override
  String toString() =>
      'PodSessionResyncRequired(sequence: $synchronizedEapSequence)';
}
