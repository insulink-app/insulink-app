import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';

void main() {
  group('the two pod UUIDs are different things', () {
    /// A scan filters on the SHORT id the pod advertises, expanded into the
    /// Bluetooth base UUID. The GATT service on the connected device is a vendor
    /// 128-bit UUID that appears nowhere in the advertisement. Filtering a scan on
    /// the GATT one finds nothing at all, which is invisible to every test that
    /// does not have a radio — hence this one.
    test('the scan UUID is the advertised short id in the base UUID', () {
      expect(podScanServiceUuid, '00004024-0000-1000-8000-00805f9b34fb');
      expect(podScanServiceUuid.substring(4, 8), podAdvertisedServiceId);
      expect(podScanServiceUuid.endsWith('-0000-1000-8000-00805f9b34fb'), isTrue,
          reason: 'must sit in the Bluetooth base UUID');
    });

    test('the GATT service UUID is the vendor one', () {
      expect(podServiceUuid, '1a7e4024-e3ed-4464-8b7e-751e03d0dc5f');
    });

    test('they are not the same value', () {
      expect(podServiceUuid, isNot(podScanServiceUuid));
    });

    test('both characteristics share the vendor prefix', () {
      for (final characteristic in PodCharacteristic.values) {
        expect(characteristic.uuid.startsWith('1a7e24'), isTrue,
            reason: characteristic.name);
        expect(characteristic.uuid.endsWith('-e3ed-4464-8b7e-751e03d0dc5f'), isTrue);
      }
      expect(PodCharacteristic.command.uuid,
          '1a7e2441-e3ed-4464-8b7e-751e03d0dc5f');
      expect(PodCharacteristic.data.uuid, '1a7e2442-e3ed-4464-8b7e-751e03d0dc5f');
    });

    test('every UUID is lowercase, since comparisons are made on the string', () {
      for (final uuid in [podServiceUuid, podScanServiceUuid]) {
        expect(uuid, uuid.toLowerCase());
      }
      for (final characteristic in PodCharacteristic.values) {
        expect(characteristic.uuid, characteristic.uuid.toLowerCase());
      }
    });
  });

  group('control words match the wire values', () {
    test('each has its documented byte', () {
      expect(PodControlWord.requestToSend.value, 0x00);
      expect(PodControlWord.clearToSend.value, 0x01);
      expect(PodControlWord.notAcknowledged.value, 0x02);
      expect(PodControlWord.abort.value, 0x03);
      expect(PodControlWord.success.value, 0x04);
      expect(PodControlWord.fail.value, 0x05);
      expect(PodControlWord.hello.value, 0x06);
    });

    test('the greeting carries the controller id big-endian', () {
      final hello = PodControlWord.helloFrom(4242);
      expect(hello, [0x06, 0x01, 0x04, 0x00, 0x00, 0x10, 0x92]);
    });

    test('a nack names the fragment it wants', () {
      expect(PodControlWord.nackFor(3), [0x02, 0x03]);
    });
  });
}
