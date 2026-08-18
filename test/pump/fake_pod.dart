import 'dart:collection';
import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/payload_fragments.dart';
import 'package:insulink/src/pump/protocol/payload_reassembler.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';

/// A scripted pod on the other end of a [PodLink].
///
/// It speaks the real control-word protocol — request-to-send, clear-to-send,
/// fragments, success — and reassembles what the driver sends, so the driver's
/// framing and sequencing are exercised rather than mocked away. What a pod
/// would compute is supplied by [onMessage], which each test fills in.
class FakePodLink implements PodLink {
  FakePodLink({required this.onMessage});

  /// Answers a message the driver sent. Returning null means the pod stays
  /// silent, which is how a timeout is simulated.
  final Future<MessagePacket?> Function(MessagePacket request) onMessage;

  /// Everything the driver sent, in order — for asserting on the exchange.
  final List<MessagePacket> received = <MessagePacket>[];

  /// Set to drop the next reply entirely, simulating a lost confirmation.
  bool swallowNextReply = false;

  final Map<PodCharacteristic, Queue<Uint8List>> _inbox = {
    PodCharacteristic.command: Queue<Uint8List>(),
    PodCharacteristic.data: Queue<Uint8List>(),
  };

  PodReassembler? _incoming;
  List<Uint8List>? _outgoing;
  int _outgoingIndex = 0;

  @override
  Future<void> write(PodCharacteristic characteristic, Uint8List frame) async {
    if (characteristic == PodCharacteristic.command) {
      await _handleControl(frame);
      return;
    }
    _handleFragment(frame);
  }

  @override
  Future<Uint8List?> read(PodCharacteristic characteristic, Duration timeout) async {
    final queue = _inbox[characteristic]!;
    if (queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }

  @override
  Uint8List? peek(PodCharacteristic characteristic) {
    final queue = _inbox[characteristic]!;
    return queue.isEmpty ? null : queue.first;
  }

  @override
  void flush(PodCharacteristic characteristic) => _inbox[characteristic]!.clear();

  /// Has the pod ask to send [message] without having been prompted, the way a
  /// real pod answers a command it already received.
  void queueUnsolicited(MessagePacket message) {
    _outgoing = PodFragmenter(message.toBytes()).fragments;
    _outgoingIndex = 0;
    _send(PodCharacteristic.command, PodControlWord.requestToSend.frame);
  }

  void _send(PodCharacteristic characteristic, Uint8List frame) =>
      _inbox[characteristic]!.add(frame);

  Future<void> _handleControl(Uint8List frame) async {
    final word = PodControlWord.byValue(frame.isEmpty ? -1 : frame[0]);
    switch (word) {
      case PodControlWord.hello:
        return;
      case PodControlWord.requestToSend:
        _incoming = null;
        _send(PodCharacteristic.command, PodControlWord.clearToSend.frame);
      case PodControlWord.clearToSend:
        _flushOutgoing();
      case PodControlWord.success:
      case PodControlWord.abort:
      case PodControlWord.fail:
        _outgoing = null;
      case PodControlWord.notAcknowledged:
        _resend(frame.length > 1 ? frame[1] : 0);
      default:
        return;
    }
  }

  void _handleFragment(Uint8List frame) {
    final joiner = _incoming ??= PodReassembler(frame);
    if (!identical(joiner, _incoming) || _incoming!.isComplete) {
      return;
    }
    if (frame[0] != 0) {
      joiner.accumulate(frame);
    }
    if (!joiner.isComplete) {
      return;
    }
    final message = MessagePacket.parse(joiner.finish());
    received.add(message);
    _incoming = null;
    _send(PodCharacteristic.command, PodControlWord.success.frame);
    _queueReply(message);
  }

  void _queueReply(MessagePacket request) {
    if (swallowNextReply) {
      swallowNextReply = false;
      return;
    }
    onMessage(request).then((reply) {
      if (reply == null) {
        return;
      }
      _outgoing = PodFragmenter(reply.toBytes()).fragments;
      _outgoingIndex = 0;
      _send(PodCharacteristic.command, PodControlWord.requestToSend.frame);
    });
  }

  void _flushOutgoing() {
    final fragments = _outgoing;
    if (fragments == null) {
      return;
    }
    for (; _outgoingIndex < fragments.length; _outgoingIndex++) {
      _send(PodCharacteristic.data, fragments[_outgoingIndex]);
    }
  }

  void _resend(int index) {
    final fragments = _outgoing;
    if (fragments != null && index < fragments.length) {
      _send(PodCharacteristic.data, fragments[index]);
    }
  }
}
