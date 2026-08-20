import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_crc.dart';

/// The command opcodes the pod accepts. The three delivery programs are always
/// preceded by a [programInsulin] interlock carrying the same numbers, which is
/// what lets the pod cross-check a delivery request against itself.
enum PodCommandType {
  setUniqueId(0x03),
  getVersion(0x07),
  getStatus(0x0e),
  silenceAlerts(0x11),
  programBasal(0x13),
  programTempBasal(0x16),
  programBolus(0x17),
  programAlerts(0x19),
  programInsulin(0x1a),
  deactivate(0x1c),
  programBeeps(0x1e),
  stopDelivery(0x1f);

  const PodCommandType(this.value);

  final int value;
}

/// The address a pod answers to before it has been given its own unique id.
const int podUnassignedUniqueId = 0xFFFFFFFF;

/// The nonce every command that carries one must send.
///
/// The DASH pod dropped its predecessor's rolling nonce for a FIXED value, and it
/// is not zero: `0x494E532E`, the ASCII bytes `INS.`. The reference driver hard
/// codes the same number with the note "the Omnipod Dash seems to use a fixed
/// nonce", and its published command vectors all carry it.
///
/// A pod refuses a wrong one. It answered ours with a NAK code that does not even
/// appear in the reference's error list, which is what an undocumented
/// nonce-mismatch looks like from the outside.
const int podFixedNonce = 0x494E532E;

/// Shared framing for everything sent to the pod: a 6-byte header carrying the
/// pod id, the command sequence number and the body length, and a trailing
/// CRC-16 over the whole thing.
///
/// The sequence number is only 4 bits wide on the wire. It is what lets the pod
/// recognise a command it has already run, so a retried delivery is executed
/// once rather than twice — never reuse a number for a different command, and
/// never skip one to "resync".
abstract class PodCommand {
  PodCommand({
    required this.uniqueId,
    required this.sequenceNumber,
    this.multiCommand = false,
  });

  static const int headerLength = 6;

  final int uniqueId;
  final int sequenceNumber;
  final bool multiCommand;

  PodCommandType get type;

  /// The full frame, header and CRC included, ready to be wrapped in a message.
  Uint8List get encoded;

  /// Builds the 6-byte header. [bodyLength] counts the command body only, not
  /// the header and not the CRC.
  Uint8List buildHeader(int bodyLength, {int? addressedTo}) {
    final header = Uint8List(headerLength);
    final view = ByteData.view(header.buffer);
    view.setUint32(0, addressedTo ?? uniqueId);
    view.setUint16(
      4,
      ((sequenceNumber & 0x0f) << 10) | (bodyLength & 0x3ff) | (multiCommand ? 1 << 15 : 0),
    );
    return header;
  }

  /// Appends the CRC-16 the pod checks before it acts on a command.
  Uint8List appendCrc(Uint8List frame) {
    final out = Uint8List(frame.length + 2);
    out.setRange(0, frame.length, frame);
    ByteData.view(out.buffer).setUint16(frame.length, PodCrc16(frame).value);
    return out;
  }

  /// Concatenates the parts of a frame in order.
  Uint8List joinParts(List<List<int>> parts) {
    final total = parts.fold<int>(0, (sum, part) => sum + part.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final part in parts) {
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }

  Uint8List bigEndian32(int value) {
    final out = Uint8List(4);
    ByteData.view(out.buffer).setUint32(0, value & 0xFFFFFFFF);
    return out;
  }

  Uint8List bigEndian16(int value) {
    final out = Uint8List(2);
    ByteData.view(out.buffer).setUint16(0, value & 0xFFFF);
    return out;
  }
}
