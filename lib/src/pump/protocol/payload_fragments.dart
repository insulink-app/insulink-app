import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_crc.dart';

/// A message is longer than one BLE write, so it travels as up to 15 numbered
/// 20-byte fragments. Both directions carry a CRC-32 over the whole payload, so
/// a lost or reordered fragment is caught before anything is decrypted.
///
/// Fragment shapes, by index:
///  - index 0 ("first"): `00 | count | [crc32 | size] | data`. The crc32+size
///    fields are only present when `count == 0`, i.e. the payload fits without
///    middle fragments; otherwise the header is just the two leading bytes.
///  - middle: `idx | data` (19 data bytes).
///  - last (idx == count): `idx | size | crc32 | data`.
///  - optional plus-one (idx == count + 1): `idx | size | data`, used when the
///    tail does not fit in the last fragment.
class PodFragmentSizes {
  static const int frame = 20;
  static const int firstHeaderWithoutMiddle = 7;
  static const int firstHeaderWithMiddle = 2;
  static const int firstCapacityWithoutMiddle =
      frame - firstHeaderWithoutMiddle;
  static const int firstCapacityWithMiddle = frame - firstHeaderWithMiddle;
  static const int singlePacketCapacity = 18;
  static const int middleCapacity = 19;
  static const int lastHeader = 6;
  static const int lastCapacity = frame - lastHeader;
  static const int maxFragments = 15;
}

/// Raised when a received fragment does not fit the expected sequence.
class PodFragmentException implements Exception {
  PodFragmentException(this.message);

  final String message;

  @override
  String toString() => 'PodFragmentException: $message';
}

/// Splits one message payload into the BLE fragments that carry it.
class PodFragmenter {
  PodFragmenter(this.payload);

  final Uint8List payload;

  List<Uint8List> get fragments {
    if (payload.length <= PodFragmentSizes.singlePacketCapacity) {
      return _splitShort();
    }
    return _splitLong();
  }

  List<Uint8List> _splitShort() {
    final crc = PodCrc32(payload).value;
    final head = payload.length < PodFragmentSizes.firstCapacityWithoutMiddle
        ? payload.length
        : PodFragmentSizes.firstCapacityWithoutMiddle;
    final first = Uint8List(PodFragmentSizes.frame);
    first[0] = 0;
    first[1] = 0;
    ByteData.view(first.buffer).setUint32(2, crc);
    first[6] = payload.length & 0xFF;
    first.setRange(7, 7 + head, payload);
    final out = <Uint8List>[first];
    if (payload.length > head) {
      out.add(_plusOne(1, payload.sublist(head)));
    }
    return out;
  }

  List<Uint8List> _splitLong() {
    final crc = PodCrc32(payload).value;
    final middleCount =
        (payload.length - PodFragmentSizes.firstCapacityWithMiddle) ~/
        PodFragmentSizes.middleCapacity;
    final rest =
        payload.length -
        middleCount * PodFragmentSizes.middleCapacity -
        PodFragmentSizes.firstCapacityWithMiddle;

    final first = Uint8List(PodFragmentSizes.frame);
    first[0] = 0;
    first[1] = middleCount + 1;
    first.setRange(
      2,
      PodFragmentSizes.frame,
      payload.sublist(0, PodFragmentSizes.firstCapacityWithMiddle),
    );
    final out = <Uint8List>[first];

    for (var index = 1; index <= middleCount; index++) {
      final start =
          PodFragmentSizes.firstCapacityWithMiddle +
          (index - 1) * PodFragmentSizes.middleCapacity;
      final middle = Uint8List(PodFragmentSizes.frame);
      middle[0] = index;
      middle.setRange(
        1,
        PodFragmentSizes.frame,
        payload.sublist(start, start + PodFragmentSizes.middleCapacity),
      );
      out.add(middle);
    }

    final tailStart =
        PodFragmentSizes.firstCapacityWithMiddle +
        middleCount * PodFragmentSizes.middleCapacity;
    final inLast = rest < PodFragmentSizes.lastCapacity
        ? rest
        : PodFragmentSizes.lastCapacity;
    final last = Uint8List(PodFragmentSizes.frame);
    last[0] = middleCount + 1;
    last[1] = rest & 0xFF;
    ByteData.view(last.buffer).setUint32(2, crc);
    last.setRange(
      PodFragmentSizes.lastHeader,
      PodFragmentSizes.lastHeader + inLast,
      payload.sublist(tailStart, tailStart + inLast),
    );
    out.add(last);

    if (rest > PodFragmentSizes.lastCapacity) {
      out.add(_plusOne(middleCount + 2, payload.sublist(tailStart + inLast)));
    }
    return out;
  }

  Uint8List _plusOne(int index, Uint8List tail) {
    final packet = Uint8List(PodFragmentSizes.frame);
    packet[0] = index;
    packet[1] = tail.length & 0xFF;
    packet.setRange(2, 2 + tail.length, tail);
    return packet;
  }
}
