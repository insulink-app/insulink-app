import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/milenage.dart';
import 'package:insulink/src/pump/protocol/pod_eap.dart';
import 'package:insulink/src/pump/protocol/pod_eap_bytes.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';

/// Recognises the pod rejecting our EAP sequence number, and recovers the
/// counter it offers instead.
///
/// The offered counter is not taken on trust: the pod signs it, and that
/// signature is recomputed and compared before [PodSessionResyncRequired] is
/// raised. Accepting an unverified counter would let anything in radio range
/// steer our sequence number.
class PodEapResync {
  PodEapResync({
    required this.longTermKey,
    required this.eapSequence,
    required this.challengeRandom,
  });

  final Uint8List longTermKey;
  final int eapSequence;
  final Uint8List challengeRandom;

  /// Throws [PodSessionResyncRequired] if [reply] is a synchronisation failure
  /// carrying a counter that verifies. Returns normally otherwise.
  void throwIfNeeded(PodEapMessage reply) {
    if (reply.subType != PodEapMessage.subTypeSynchronizationFailure ||
        reply.attributes.length != 1 ||
        reply.attributes.single.type != PodEapAttributeType.auts) {
      return;
    }
    final auts = reply.attributes.single.payload;
    final offered = Milenage(
      key: longTermKey,
      sqn: encodeEapSequence(eapSequence),
      rand: challengeRandom,
      auts: auts,
    ).synchronizationSqn;
    final verified = Milenage(
      key: longTermKey,
      sqn: offered,
      rand: challengeRandom,
      auts: auts,
      amf: Uint8List.fromList(Milenage.resyncAmf),
    );
    if (!constantTimeEquals(verified.macS, verified.receivedMacS)) {
      throw PodSessionException('Pod resynchronisation failed its own signature');
    }
    throw PodSessionResyncRequired(decodeEapSequence(offered));
  }
}
