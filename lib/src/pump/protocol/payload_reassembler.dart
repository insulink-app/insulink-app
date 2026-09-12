import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/payload_fragments.dart';
import 'package:insulink/src/pump/protocol/pod_crc.dart';

/// Rebuilds one message payload from the BLE fragments the pod sends.
///
/// Fragments must arrive in order; an index that skips or repeats aborts the
/// message rather than being tolerated, because a silently mis-assembled
/// payload would be handed on as a pod status or a command acknowledgement.
/// The trailing CRC-32 check is the second gate on the same risk.
class PodReassembler {
  PodReassembler(Uint8List firstFragment) {
    if (firstFragment.length < PodFragmentSizes.firstHeaderWithMiddle) {
      throw PodFragmentException('First fragment too short');
    }
    if (firstFragment[0] != 0) {
      throw PodFragmentException(
        'Expected fragment index 0, got ${firstFragment[0]}',
      );
    }
    _fullFragments = firstFragment[1];
    if (_fullFragments >= PodFragmentSizes.maxFragments) {
      throw PodFragmentException(
        'Too many fragments announced: $_fullFragments',
      );
    }
    if (_fullFragments == 0) {
      if (firstFragment.length < PodFragmentSizes.firstHeaderWithoutMiddle) {
        throw PodFragmentException('Single-fragment message truncated');
      }
      final announced = firstFragment[6];
      final end = _min(
        announced + PodFragmentSizes.firstHeaderWithoutMiddle,
        firstFragment.length,
      );
      _crc = ByteData.view(
        firstFragment.buffer,
        firstFragment.offsetInBytes,
      ).getUint32(2);
      _expectsExtra =
          announced + PodFragmentSizes.firstHeaderWithoutMiddle > end;
      _parts.add(
        firstFragment.sublist(PodFragmentSizes.firstHeaderWithoutMiddle, end),
      );
      return;
    }
    if (firstFragment.length < PodFragmentSizes.frame) {
      throw PodFragmentException(
        'Multi-fragment first packet must be full length',
      );
    }
    _parts.add(
      firstFragment.sublist(
        PodFragmentSizes.firstHeaderWithMiddle,
        PodFragmentSizes.frame,
      ),
    );
  }

  final List<Uint8List> _parts = <Uint8List>[];
  late final int _fullFragments;
  int _crc = 0;
  bool _expectsExtra = false;
  int _expectedIndex = 0;

  /// Whether every fragment of the message has arrived.
  bool get isComplete {
    final last = _expectsExtra ? _fullFragments + 1 : _fullFragments;
    return _expectedIndex >= last;
  }

  void accumulate(Uint8List fragment) {
    if (fragment.length < 3) {
      throw PodFragmentException('Fragment too short');
    }
    final index = fragment[0];
    if (index != _expectedIndex + 1) {
      throw PodFragmentException(
        'Expected fragment ${_expectedIndex + 1}, got $index',
      );
    }
    _expectedIndex++;
    if (index < _fullFragments) {
      _parts.add(fragment.sublist(1, PodFragmentSizes.frame));
      return;
    }
    if (index == _fullFragments) {
      final announced = fragment[1];
      final end = _min(
        announced + PodFragmentSizes.lastHeader,
        fragment.length,
      );
      _crc = ByteData.view(
        fragment.buffer,
        fragment.offsetInBytes,
      ).getUint32(2);
      _expectsExtra = announced + PodFragmentSizes.lastHeader > end;
      _parts.add(fragment.sublist(PodFragmentSizes.lastHeader, end));
      return;
    }
    if (index == _fullFragments + 1 && _expectsExtra) {
      final announced = fragment[1];
      if (fragment.length < 2 + announced) {
        throw PodFragmentException('Trailing fragment truncated');
      }
      _parts.add(fragment.sublist(2, 2 + announced));
      return;
    }
    throw PodFragmentException('Unexpected fragment index $index');
  }

  /// Concatenates the fragments and verifies the announced CRC-32.
  Uint8List finish() {
    final total = _parts.fold<int>(0, (sum, part) => sum + part.length);
    final joined = Uint8List(total);
    var offset = 0;
    for (final part in _parts) {
      joined.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    final actual = PodCrc32(joined).value;
    if (actual != _crc) {
      throw PodFragmentException(
        'CRC mismatch: computed $actual, announced $_crc',
      );
    }
    return joined;
  }

  static int _min(int left, int right) => left < right ? left : right;
}
