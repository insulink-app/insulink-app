import 'package:flutter_test/flutter_test.dart';
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
}
