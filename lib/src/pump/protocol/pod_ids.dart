import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_command.dart';

/// A 4-byte node address on the pod's message bus. The controller (this app)
/// and the pod each have one, and every message carries both.
class PodId {
  PodId(this.address) : assert(address.length == 4);

  /// Builds an id from a 32-bit value, big-endian as the wire uses it.
  factory PodId.fromInt(int value) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, value & 0xFFFFFFFF);
    return PodId(bytes);
  }

  final Uint8List address;

  /// The address a pod that has never been activated answers on.
  static final PodId notActivated = PodId.fromInt(0xFFFFFFFE);

  /// Derives the pod's address from the controller's, used until the pod has
  /// been given its own unique id. The real PDM rotates over controllerId+1..+3;
  /// index 1 is the one the activation flow uses.
  PodId get peripheral {
    final derived = Uint8List.fromList(address);
    derived[3] = (derived[3] & ~0x03) | 0x01;
    return PodId(derived);
  }

  int get value =>
      ByteData.view(address.buffer, address.offsetInBytes).getUint32(0);

  @override
  bool operator ==(Object other) => other is PodId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// The address pair for one pod link: this controller and the pod it talks to.
///
/// [controllerId] is fixed rather than random so a reinstall keeps talking to
/// an already-activated pod; the pod stores the controller address it was
/// activated with and ignores anyone else.
class PodAddressPair {
  const PodAddressPair({required this.podUniqueId});

  /// The controller address this app identifies as. Matches the value the
  /// other open implementations use, so a pod activated by one is reachable by
  /// the other.
  static const int controllerId = 4242;

  /// The pod's assigned unique id, or null while it is not yet activated.
  final int? podUniqueId;

  PodId get myId => PodId.fromInt(controllerId);

  /// Whether a reply carrying [replyId] came from the pod we are talking to.
  ///
  /// [podUnassignedUniqueId] counts, and has to: a pod answers with it until it
  /// has been GIVEN its id, which happens two commands into an activation. The
  /// version read that precedes it is answered by a pod that does not yet know
  /// what to call itself, so refusing that id fails the first command of every
  /// activation.
  bool acceptsReplyFrom(int replyId) =>
      replyId == podId.value || replyId == podUnassignedUniqueId;

  PodId get podId {
    final assigned = podUniqueId;
    if (assigned == null) {
      return myId.peripheral;
    }
    return PodId.fromInt(assigned);
  }
}
