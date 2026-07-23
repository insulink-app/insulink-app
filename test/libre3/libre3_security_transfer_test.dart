import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/libre3/libre3_security_transfer.dart';

/// One `[sequence, ...data]` fragment carrying [length] bytes of filler.
List<int> fragment(int sequence, int length, {int fill = 0xAA}) =>
    [sequence, ...List<int>.filled(length, fill)];

void main() {
  group('Libre3SecurityTransfer', () {
    test('reassembles a multi-fragment transfer in order', () {
      final transfer = Libre3SecurityTransfer()..expect(40);
      expect(transfer.add(fragment(0, 19)), isFalse);
      expect(transfer.add(fragment(1, 19)), isFalse);
      expect(transfer.add(fragment(2, 2)), isTrue);
      expect(transfer.data.length, 40);
      expect(transfer.data.every((byte) => byte == 0xAA), isTrue);
    });

    test('a padded final fragment is clamped, not an overrun', () {
      // The sensor pads its last frame: 65 bytes announced, delivered as four
      // 19-byte fragments (76 bytes of payload). The surplus must be dropped.
      final transfer = Libre3SecurityTransfer()..expect(65);
      transfer
        ..add(fragment(0, 19))
        ..add(fragment(1, 19))
        ..add(fragment(2, 19));
      expect(transfer.add(fragment(3, 19)), isTrue);
      expect(transfer.data.length, 65);
    });

    test('a sequence gap is rejected', () {
      final transfer = Libre3SecurityTransfer()..expect(40);
      transfer.add(fragment(0, 19));
      expect(
        () => transfer.add(fragment(2, 19)),
        throwsA(isA<Libre3TransferException>()),
      );
    });

    test('a fragment before any announcement is rejected', () {
      expect(
        () => Libre3SecurityTransfer().add(fragment(0, 19)),
        throwsA(isA<Libre3TransferException>()),
      );
    });

    test('a new announcement discards a partial transfer', () {
      final transfer = Libre3SecurityTransfer()..expect(140);
      transfer.add(fragment(0, 19));
      transfer.expect(23);
      expect(transfer.add(fragment(0, 19)), isFalse);
      expect(transfer.add(fragment(1, 19)), isTrue);
      expect(transfer.data.length, 23);
    });

    test('an empty notification is ignored', () {
      final transfer = Libre3SecurityTransfer()..expect(23);
      expect(transfer.add(const []), isFalse);
    });
  });
}
