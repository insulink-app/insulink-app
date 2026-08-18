import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_aes.dart';

/// The 3GPP Milenage function set, which the pod reuses as the authentication
/// core of its EAP-AKA session handshake.
///
/// The long-term key from pairing plays the role of the SIM key K, and the
/// derived [ck] becomes the AES-CCM key protecting every later command. The
/// operator constants below are the pod's, not a real carrier's.
///
/// [auts] and [amf] are only set on the re-synchronisation path, where the pod
/// rejects our sequence number and returns its own: constructing a second
/// instance with the returned AUTS yields [synchronizationSqn] and lets
/// [macS]/[receivedMacS] be compared before the new sequence number is trusted.
class Milenage {
  Milenage({
    required Uint8List key,
    required this.sqn,
    required this.rand,
    Uint8List? auts,
    Uint8List? amf,
  })  : assert(key.length == 16),
        assert(sqn.length == 6),
        assert(rand.length == 16),
        _aes = PodAes(key),
        auts = auts ?? Uint8List(autsSize),
        amf = amf ?? Uint8List.fromList(defaultAmf) {
    _derive();
  }

  static const int autsSize = 14;
  static const List<int> defaultAmf = [0xb9, 0xb9];
  static const List<int> resyncAmf = [0x00, 0x00];
  static const List<int> _operatorConstant = [
    ***REMOVED*** //
    ***REMOVED***
  ];

  final PodAes _aes;
  final Uint8List sqn;
  final Uint8List rand;
  final Uint8List auts;
  final Uint8List amf;

  late final Uint8List res;
  late final Uint8List ck;
  late final Uint8List autn;
  late final Uint8List macS;
  late final Uint8List synchronizationSqn;
  late final Uint8List receivedMacS;

  void _derive() {
    final opc = xorBytes(
      _aes.encryptBlock(Uint8List.fromList(_operatorConstant)),
      Uint8List.fromList(_operatorConstant),
    );
    final randEncrypted = _aes.encryptBlock(xorBytes(rand, opc));
    final randMasked = xorBytes(randEncrypted, opc);

    final resInput = Uint8List.fromList(randMasked);
    resInput[15] ^= 1;
    final resAk = xorBytes(_aes.encryptBlock(resInput), opc);
    res = resAk.sublist(8, 16);
    final ak = resAk.sublist(0, 6);

    ck = xorBytes(_aes.encryptBlock(_rotated(randMasked, 12, 2)), opc);

    final sqnAmf = Uint8List.fromList(sqn + amf + sqn + amf);
    final macInput = _rotated(xorBytes(sqnAmf, opc), 8, null);
    final macFull = xorBytes(_aes.encryptBlock(xorBytes(macInput, randEncrypted)), opc);
    macS = macFull.sublist(8, 16);
    autn = Uint8List.fromList(xorBytes(ak, sqn) + amf + macFull.sublist(0, 8));

    final akStar =
        xorBytes(_aes.encryptBlock(_rotated(randMasked, 4, 8)), opc).sublist(0, 6);
    synchronizationSqn = xorBytes(akStar, auts.sublist(0, 6));
    receivedMacS = auts.sublist(6, 14);
  }

  /// Rotates [source] right by [shift] byte positions into a fresh block, then
  /// flips [lastByteMask] into the final byte — the per-function tweak that
  /// separates the CK, MAC and AK* derivations from one another.
  Uint8List _rotated(Uint8List source, int shift, int? lastByteMask) {
    final out = Uint8List(16);
    for (var index = 0; index < 16; index++) {
      out[(index + shift) % 16] = source[index];
    }
    if (lastByteMask != null) {
      out[15] ^= lastByteMask;
    }
    return out;
  }
}
