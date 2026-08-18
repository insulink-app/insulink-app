import 'dart:typed_data';

/// The pod's two GATT characteristics. Control words travel on [command],
/// message fragments on [data].
enum PodCharacteristic {
  command('1a7e2441-e3ed-4464-8b7e-751e03d0dc5f'),
  data('1a7e2442-e3ed-4464-8b7e-751e03d0dc5f');

  const PodCharacteristic(this.uuid);

  final String uuid;
}

/// The pod's BLE GATT service.
const String podServiceUuid = '1a7e4024-e3ed-4464-8b7e-751e03d0dc5f';

/// The 16-bit service id a pod advertises, used to filter a scan.
const String podAdvertisedServiceId = '4024';

/// The single-byte control words exchanged on [PodCharacteristic.command] to
/// frame each message transfer.
enum PodControlWord {
  requestToSend(0x00),
  clearToSend(0x01),
  notAcknowledged(0x02),
  abort(0x03),
  success(0x04),
  fail(0x05),
  hello(0x06);

  const PodControlWord(this.value);

  final int value;

  static PodControlWord? byValue(int value) {
    for (final word in PodControlWord.values) {
      if (word.value == value) {
        return word;
      }
    }
    return null;
  }

  Uint8List get frame => Uint8List.fromList([value]);

  /// A not-acknowledged word naming which fragment index is missing.
  static Uint8List nackFor(int index) =>
      Uint8List.fromList([notAcknowledged.value, index & 0xFF]);

  /// The greeting written once per connection, announcing our controller id.
  static Uint8List helloFrom(int controllerId) => Uint8List.fromList([
        hello.value,
        0x01,
        0x04,
        (controllerId >> 24) & 0xFF,
        (controllerId >> 16) & 0xFF,
        (controllerId >> 8) & 0xFF,
        controllerId & 0xFF,
      ]);
}

/// Raised when the link itself fails — no reply, or a write that did not land.
class PodLinkException implements Exception {
  PodLinkException(this.message);

  final String message;

  @override
  String toString() => 'PodLinkException: $message';
}

/// A connected pod's two characteristics, as a queue per characteristic.
///
/// Deliberately queue-shaped rather than stream-shaped: the protocol is a strict
/// request/response exchange where a frame that arrives early has to wait, and a
/// broadcast stream would drop it. The BLE implementation buffers notifications
/// into these queues; tests supply a scripted pod instead.
abstract class PodLink {
  /// Writes one frame and completes when the peer has acknowledged the write.
  Future<void> write(PodCharacteristic characteristic, Uint8List frame);

  /// Takes the next queued frame, waiting up to [timeout]. Null on timeout.
  Future<Uint8List?> read(PodCharacteristic characteristic, Duration timeout);

  /// Returns the next queued frame without consuming it, or null if none is
  /// waiting. Never blocks.
  Uint8List? peek(PodCharacteristic characteristic);

  /// Drops anything queued, so a new exchange does not read a stale frame.
  void flush(PodCharacteristic characteristic);
}
