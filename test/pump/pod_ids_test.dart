import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_command.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';

void main() {
  group('pod addressing', () {
    test('the pod takes the controller address with its low two bits replaced', () {
      // Pinned against the captured commands, which address a pod on 4241 from a
      // controller on 4242. Getting this wrong makes source and destination equal.
      expect(PodId.fromInt(4242).peripheral.value, 4241);
    });

    test('an unactivated pod is addressed by the derived id', () {
      const addresses = PodAddressPair(podUniqueId: null);
      expect(addresses.myId.value, PodAddressPair.controllerId);
      expect(addresses.podId.value, 4241);
      expect(addresses.myId, isNot(addresses.podId));
    });

    test('an activated pod is addressed by its assigned id', () {
      const addresses = PodAddressPair(podUniqueId: 4241);
      expect(addresses.podId.value, 4241);
    });

    test('the derived id is stable however often it is taken', () {
      final once = PodId.fromInt(4242).peripheral;
      expect(once.peripheral.value, once.value);
    });

    test('the not-activated address is the pod discovery address', () {
      expect(PodId.notActivated.value, 0xFFFFFFFE);
    });

    test('ids round-trip through their four bytes', () {
      for (final value in [0, 1, 4241, 4242, 136326825, 0xFFFFFFFE]) {
        expect(PodId.fromInt(value).value, value);
      }
    });
  });

  group('which replies count as coming from our pod', () {
    const addresses = PodAddressPair(podUniqueId: 4241);

    test('the assigned id is ours', () {
      expect(addresses.acceptsReplyFrom(4241), isTrue);
    });

    /// A pod answers with the unassigned id until it has been GIVEN one, two
    /// commands into an activation. Refusing it failed the version read at the
    /// start of every real activation.
    test('a pod that has no id yet is ours too', () {
      expect(addresses.acceptsReplyFrom(podUnassignedUniqueId), isTrue);
    });

    test('anything else is refused', () {
      expect(addresses.acceptsReplyFrom(4242), isFalse);
      expect(addresses.acceptsReplyFrom(136326825), isFalse);
      expect(addresses.acceptsReplyFrom(0), isFalse);
    });

    /// Before an id is assigned the pair derives one from the controller, and a
    /// reply from that pod is still ours.
    test('an unactivated pair accepts its derived id', () {
      const pending = PodAddressPair(podUniqueId: null);
      expect(pending.acceptsReplyFrom(pending.podId.value), isTrue);
      expect(pending.acceptsReplyFrom(podUnassignedUniqueId), isTrue);
    });
  });
}
