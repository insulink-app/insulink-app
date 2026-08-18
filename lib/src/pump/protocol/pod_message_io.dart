import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/payload_fragments.dart';
import 'package:insulink/src/pump/protocol/payload_reassembler.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';

/// Exchanges whole [MessagePacket]s over a [PodLink].
///
/// Each transfer is framed by control words on the command characteristic:
/// the sender asks with request-to-send, the receiver answers clear-to-send,
/// the fragments go over the data characteristic, and the receiver closes with
/// success. A receiver that cannot make sense of the fragments answers abort,
/// and one whose CRC does not match answers fail — the two are distinct so the
/// sender knows whether resending can help.
///
/// ponytail: fragments are expected in order; an out-of-order one is nacked and
/// awaited again rather than buffered. If field logs later show reordering on
/// this link, buffer by index the way the reference driver does.
class PodMessageIo {
  PodMessageIo(this.link);

  static const Duration _controlTimeout = Duration(seconds: 5);
  static const Duration _fragmentTimeout = Duration(seconds: 5);
  static const int _maxFragmentTries = 4;

  final PodLink link;

  /// Announces our controller id. Written once per connection, before anything
  /// else — the pod ignores traffic from a controller that has not said hello.
  Future<void> sayHello(int controllerId) {
    return link.write(
      PodCharacteristic.command,
      PodControlWord.helloFrom(controllerId),
    );
  }

  /// Sends one message and waits for the pod to confirm it.
  ///
  /// Throws [PodLinkException] if the pod never granted clear-to-send or never
  /// confirmed. A throw after the last fragment went out means the outcome is
  /// genuinely unknown — the pod may have acted on the message — so a caller
  /// that sent a delivery command must read the pod's status rather than resend.
  Future<void> sendMessage(MessagePacket message) async {
    if (link.peek(PodCharacteristic.command) != null) {
      throw PodLinkException('Pod is mid-transfer; refusing to send over it');
    }
    link.flush(PodCharacteristic.data);

    await link.write(PodCharacteristic.command, PodControlWord.requestToSend.frame);
    await _expectControl(PodControlWord.clearToSend);

    final fragments = PodFragmenter(message.toBytes()).fragments;
    for (var index = 0; index < fragments.length; index++) {
      await link.write(PodCharacteristic.data, fragments[index]);
      await _resendIfNacked(fragments, index);
    }
    await _expectControl(PodControlWord.success);
  }

  /// Waits for the pod to send a message and reassembles it.
  ///
  /// Returns null when the pod did not ask to send within the timeout, which is
  /// a normal outcome rather than an error — the caller decides whether to wait
  /// again or give up.
  Future<MessagePacket?> receiveMessage({bool expectRequestToSend = true}) async {
    if (expectRequestToSend) {
      final asked = await _readControl(_controlTimeout);
      if (asked != PodControlWord.requestToSend) {
        return null;
      }
    }
    await link.write(PodCharacteristic.command, PodControlWord.clearToSend.frame);

    try {
      final payload = await _readFragments();
      await link.write(PodCharacteristic.command, PodControlWord.success.frame);
      return MessagePacket.parse(payload);
    } on PodFragmentException catch (error) {
      final word = error.message.contains('CRC')
          ? PodControlWord.fail
          : PodControlWord.abort;
      await link.write(PodCharacteristic.command, word.frame);
      return null;
    } on PodMessageException {
      await link.write(PodCharacteristic.command, PodControlWord.abort.frame);
      return null;
    }
  }

  Future<Uint8List> _readFragments() async {
    final first = await _readFragment(0);
    final joiner = PodReassembler(first);
    var index = 0;
    while (!joiner.isComplete) {
      index++;
      joiner.accumulate(await _readFragment(index));
    }
    return joiner.finish();
  }

  /// Reads the fragment at [index], nacking anything else so the pod resends.
  Future<Uint8List> _readFragment(int index) async {
    for (var attempt = 0; attempt < _maxFragmentTries; attempt++) {
      final frame = await link.read(PodCharacteristic.data, _fragmentTimeout);
      if (frame != null && frame.isNotEmpty && frame[0] == index) {
        return frame;
      }
      await link.write(PodCharacteristic.command, PodControlWord.nackFor(index));
    }
    throw PodFragmentException('Pod never sent fragment $index');
  }

  /// Resends a fragment the pod says it missed, and rejects a premature success.
  Future<void> _resendIfNacked(List<Uint8List> fragments, int index) async {
    final pending = link.peek(PodCharacteristic.command);
    if (pending == null || pending.isEmpty) {
      return;
    }
    final word = PodControlWord.byValue(pending[0]);
    if (word == PodControlWord.notAcknowledged) {
      await link.read(PodCharacteristic.command, _controlTimeout);
      final missing = pending.length > 1 ? pending[1] : 0;
      if (missing >= fragments.length) {
        throw PodLinkException('Pod asked to resend fragment $missing, which does not exist');
      }
      await link.write(PodCharacteristic.data, fragments[missing]);
      return;
    }
    if (word == PodControlWord.success && index != fragments.length - 1) {
      throw PodLinkException('Pod confirmed before all fragments were sent');
    }
  }

  Future<PodControlWord?> _readControl(Duration timeout) async {
    final frame = await link.read(PodCharacteristic.command, timeout);
    if (frame == null || frame.isEmpty) {
      return null;
    }
    return PodControlWord.byValue(frame[0]);
  }

  Future<void> _expectControl(PodControlWord expected) async {
    final word = await _readControl(_controlTimeout);
    if (word == expected) {
      return;
    }
    if (word == PodControlWord.fail) {
      throw PodLinkException('Pod rejected the message (fail)');
    }
    throw PodLinkException('Expected ${expected.name}, got ${word?.name ?? 'nothing'}');
  }
}
