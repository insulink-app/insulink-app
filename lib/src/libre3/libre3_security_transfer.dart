import 'dart:math';
import 'dart:typed_data';

/// Thrown when a cert/challenge transfer violates its framing — an unannounced
/// fragment or a sequence gap. Both mean the security channel is desynchronised,
/// so the handshake must fail immediately rather than reassemble garbage.
class Libre3TransferException implements Exception {
  Libre3TransferException(this.message);

  final String message;

  @override
  String toString() => 'Libre3TransferException: $message';
}

/// Reassembles ONE sequence-numbered cert/challenge transfer on the Libre 3
/// security channel (Juggluco's `preparedata` + `getsecdata`): COMMAND_RESPONSE
/// announces the total length, then CERT_DATA/CHALLENGE_DATA delivers
/// `[sequence, ...data]` fragments with an incrementing sequence byte.
///
/// A fragment may carry MORE bytes than the transfer still needs — the sensor
/// pads its last frame the same way our writes do — so the copy is clamped to
/// the announced length. Without the clamp the surplus overran the destination
/// and threw inside the notification listener, where nothing catches it: the
/// handshake then stalled silently until its 40 s timeout instead of failing
/// with a readable reason.
class Libre3SecurityTransfer {
  int _length = 0;
  Uint8List _data = Uint8List(0);
  int _received = 0;
  int _sequence = -1;

  /// The announced total size of the transfer in progress, 0 when idle.
  int get length => _length;

  /// The bytes reassembled so far — meaningful once [add] reported completion.
  Uint8List get data => _data;

  /// Start a new transfer of [length] bytes, discarding any partial one.
  void expect(int length) {
    _length = length;
    _data = Uint8List(length);
    _received = 0;
    _sequence = -1;
  }

  /// Append one `[sequence, ...data]` fragment. Returns true once the announced
  /// length is complete.
  bool add(List<int> fragment) {
    if (fragment.isEmpty) {
      return false;
    }
    _rejectUnexpected(fragment.first);
    final take = min(fragment.length - 1, _length - _received);
    _data.setRange(_received, _received + take, fragment, 1);
    _received += take;
    _sequence = fragment.first;
    return _received >= _length;
  }

  /// Guard the two framing violations: a fragment nobody announced, and a
  /// sequence byte that skipped or repeated a frame.
  void _rejectUnexpected(int sequence) {
    if (_length == 0) {
      throw Libre3TransferException(
        'sec data fragment before any transfer announcement',
      );
    }
    if (sequence != _sequence + 1) {
      throw Libre3TransferException(
        'sec data out of sequence: $sequence != ${_sequence + 1}',
      );
    }
  }
}
