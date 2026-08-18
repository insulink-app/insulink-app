import 'dart:math';
import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_aes.dart';
import 'package:insulink/src/rust/api/x25519.dart';

/// Raised when the pod's side of the pairing does not verify.
class PodPairingException implements Exception {
  PodPairingException(this.message);

  final String message;

  @override
  String toString() => 'PodPairingException: $message';
}

/// The pairing key ladder that turns an X25519 exchange into the pod's
/// long-term key (LTK) plus the two confirmation values that prove both sides
/// derived the same one.
///
/// Sequence: we send our public key and nonce, the pod answers with its own,
/// both sides derive the LTK, and each sends the confirmation value the other
/// can recompute. [podConfirmation] must be checked against what the pod sends
/// BEFORE the pairing is accepted — it is the only evidence that we are talking
/// to the pod we think we are and that it holds the same key.
///
/// The magic strings and the ladder shape are the pod's; they are reproduced
/// exactly and pinned by the known-answer test in `test/pump/pod_pairing_test.dart`.
class PodKeyExchange {
  PodKeyExchange({required this.privateKey, required this.controllerNonce})
      : assert(privateKey.length == 32),
        assert(controllerNonce.length == nonceSize),
        publicKey = x25519PublicFromPrivate(privateKey: privateKey);

  /// Builds an exchange with a freshly generated key pair and nonce.
  factory PodKeyExchange.generate() {
    final random = Random.secure();
    return PodKeyExchange(
      privateKey: x25519GeneratePrivateKey(),
      controllerNonce: Uint8List.fromList(
        List<int>.generate(nonceSize, (_) => random.nextInt(256)),
      ),
    );
  }

  static const int nonceSize = 16;
  static const int publicKeySize = 32;
  static const int keySize = 16;
  static const List<int> _ladderLabel = [0x54, 0x57, 0x49, 0x74]; // "TWIt"
  static const List<int> _controllerConfirmLabel = [0x4b, 0x43, 0x5f, 0x32, 0x5f, 0x55]; // "KC_2_U"
  static const List<int> _podConfirmLabel = [0x4b, 0x43, 0x5f, 0x32, 0x5f, 0x56]; // "KC_2_V"

  final Uint8List privateKey;
  final Uint8List controllerNonce;
  final Uint8List publicKey;

  late final Uint8List podPublicKey;
  late final Uint8List podNonce;

  /// The pod's long-term key. Stored and reused for every later session.
  late final Uint8List longTermKey;

  /// What we send the pod so it can check us.
  late final Uint8List controllerConfirmation;

  /// What the pod must send us. Compare with [verifyPodConfirmation].
  late final Uint8List podConfirmation;

  bool _derived = false;

  /// The 48-byte block we put on the wire: public key followed by nonce.
  Uint8List get offer => Uint8List.fromList(publicKey + controllerNonce);

  /// Consumes the pod's public key and nonce and runs the ladder.
  void acceptPodOffer(Uint8List payload) {
    if (payload.length != publicKeySize + nonceSize) {
      throw PodPairingException(
        'Pod offer must be ${publicKeySize + nonceSize} bytes, got ${payload.length}',
      );
    }
    podPublicKey = Uint8List.sublistView(payload, 0, publicKeySize);
    podNonce = Uint8List.sublistView(payload, publicKeySize);
    _derive();
  }

  void _derive() {
    final shared = x25519SharedSecret(
      privateKey: privateKey,
      peerPublicKey: podPublicKey,
    );
    final seedKey = Uint8List.fromList(
      _tail(podPublicKey) + _tail(publicKey) + _tail(podNonce) + _tail(controllerNonce),
    );
    final intermediate = PodAes(seedKey).cmac(shared);

    longTermKey = PodAes(intermediate).cmac(_ladderInput(0x02));
    final confirmKey = PodAes(intermediate).cmac(_ladderInput(0x01));

    controllerConfirmation = PodAes(confirmKey).cmac(
      Uint8List.fromList(_controllerConfirmLabel + controllerNonce + podNonce),
    );
    podConfirmation = PodAes(confirmKey).cmac(
      Uint8List.fromList(_podConfirmLabel + podNonce + controllerNonce),
    );
    _derived = true;
  }

  Uint8List _ladderInput(int selector) {
    return Uint8List.fromList(
      [selector] + _ladderLabel + podNonce + controllerNonce + [0x00, 0x01],
    );
  }

  Uint8List _tail(Uint8List source) => source.sublist(source.length - 4);

  /// Checks the pod's confirmation value. A mismatch means the pairing did not
  /// agree on a key, so it must abort rather than continue with a guess.
  void verifyPodConfirmation(Uint8List received) {
    if (!_derived) {
      throw PodPairingException('Pod offer not processed yet');
    }
    if (received.length != podConfirmation.length) {
      throw PodPairingException('Pod confirmation has the wrong length');
    }
    var mismatch = 0;
    for (var index = 0; index < received.length; index++) {
      mismatch |= received[index] ^ podConfirmation[index];
    }
    if (mismatch != 0) {
      throw PodPairingException('Pod confirmation mismatch — aborting pairing');
    }
  }
}
