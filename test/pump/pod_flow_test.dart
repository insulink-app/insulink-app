import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/key_exchange.dart';
import 'package:insulink/src/pump/protocol/message_packet.dart';
import 'package:insulink/src/pump/protocol/milenage.dart';
import 'package:insulink/src/pump/protocol/pod_aes.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_eap.dart';
import 'package:insulink/src/pump/protocol/pod_ids.dart';
import 'package:insulink/src/pump/protocol/pod_link.dart';
import 'package:insulink/src/pump/protocol/pod_message_io.dart';
import 'package:insulink/src/pump/protocol/pod_pairing.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/pod_session.dart';
import 'package:insulink/src/pump/protocol/pod_session_establisher.dart';
import 'package:insulink/src/pump/protocol/pod_session_keys.dart';
import 'package:insulink/src/pump/protocol/session_cipher.dart';
import 'package:insulink/src/pump/protocol/string_prefix_codec.dart';
import 'package:insulink/src/rust/api/x25519.dart';
import 'package:insulink/src/rust/frb_generated.dart';

import 'fake_pod.dart';

import 'vendor_keys_fixture.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

String toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List tail4(Uint8List source) => source.sublist(source.length - 4);

/// The pod's own side of the pairing ladder, computed independently of the
/// driver so that agreeing on a key means something.
class PodSideKeyExchange {
  PodSideKeyExchange({required this.privateKey, required this.nonce})
      : publicKey = x25519PublicFromPrivate(privateKey: privateKey);

  final Uint8List privateKey;
  final Uint8List nonce;
  final Uint8List publicKey;

  late Uint8List longTermKey;
  late Uint8List podConfirmation;
  late Uint8List controllerConfirmation;

  void accept(Uint8List controllerOffer) {
    final controllerPublic = controllerOffer.sublist(0, 32);
    final controllerNonce = controllerOffer.sublist(32);
    final shared = x25519SharedSecret(
      privateKey: privateKey,
      peerPublicKey: controllerPublic,
    );
    final seed = Uint8List.fromList(
      tail4(publicKey) + tail4(controllerPublic) + tail4(nonce) + tail4(controllerNonce),
    );
    final intermediate = PodAes(seed).cmac(shared);
    Uint8List ladder(int selector) => Uint8List.fromList(
        [selector] + 'TWIt'.codeUnits + nonce + controllerNonce + [0x00, 0x01]);
    longTermKey = PodAes(intermediate).cmac(ladder(0x02));
    final confirmKey = PodAes(intermediate).cmac(ladder(0x01));
    controllerConfirmation = PodAes(confirmKey)
        .cmac(Uint8List.fromList('KC_2_U'.codeUnits + controllerNonce + nonce));
    podConfirmation = PodAes(confirmKey)
        .cmac(Uint8List.fromList('KC_2_V'.codeUnits + nonce + controllerNonce));
  }
}

void main() {
  setUpAll(() async {
    final library = File('rust/target/debug/librust_lib_insulink.so');
    if (!library.existsSync()) {
      throw StateError('Run `cd rust && cargo build` before this test.');
    }
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(library.absolute.path),
    );
  });

  group('PodMessageIo', () {
    test('sends a message and reads the pod reply through the control flow', () async {
      late MessagePacket seen;
      final link = FakePodLink(onMessage: (request) async {
        seen = request;
        return request.withPayload(Uint8List.fromList([1, 2, 3, 4, 5]));
      });
      final io = PodMessageIo(link);
      await io.sayHello(PodAddressPair.controllerId);

      final sent = MessagePacket(
        type: PodMessageType.clear,
        source: PodId.fromInt(4242),
        destination: PodId.fromInt(4243),
        payload: Uint8List.fromList(List<int>.generate(60, (index) => index)),
        sequenceNumber: 3,
      );
      await io.sendMessage(sent);
      expect(toHex(seen.payload), toHex(sent.payload));

      final reply = await io.receiveMessage();
      expect(reply, isNotNull);
      expect(toHex(reply!.payload), '0102030405');
    });

    test('a message spanning many fragments survives the round trip', () async {
      final body = Uint8List.fromList(
          List<int>.generate(200, (index) => (index * 13 + 7) & 0xFF));
      late MessagePacket seen;
      final link = FakePodLink(onMessage: (request) async {
        seen = request;
        return null;
      });
      await PodMessageIo(link).sendMessage(MessagePacket(
        type: PodMessageType.clear,
        source: PodId.fromInt(1),
        destination: PodId.fromInt(2),
        payload: body,
        sequenceNumber: 1,
      ));
      expect(toHex(seen.payload), toHex(body));
    });

    /// The pod sends a burst, and the queue can surface it out of order. A driver
    /// that discarded the early fragment would have to ask for it again.
    test('a burst that arrives out of order is still reassembled', () async {
      final body = Uint8List.fromList(
          List<int>.generate(120, (index) => (index * 5 + 1) & 0xFF));
      late FakePodLink link;
      link = FakePodLink(onMessage: (request) async {
        link.reorderFragments = true;
        return request.withPayload(body);
      });
      final io = PodMessageIo(link);
      await io.sendMessage(MessagePacket(
        type: PodMessageType.clear,
        source: PodId.fromInt(1),
        destination: PodId.fromInt(2),
        payload: Uint8List.fromList([1, 2, 3]),
        sequenceNumber: 1,
      ));
      final reply = await io.receiveMessage();
      expect(reply, isNotNull);
      expect(toHex(reply!.payload), toHex(body));
    });

    /// A leftover word from a finished exchange must not abort the next one. During
    /// pairing that would cost a pod for no reason.
    test('a stale control word is discarded rather than aborting the send', () async {
      late FakePodLink link;
      link = FakePodLink(onMessage: (request) async => null);
      // Leave a spent success word behind, as a real link can.
      link.seedControl(PodControlWord.success.frame);
      final io = PodMessageIo(link);
      await io.sendMessage(MessagePacket(
        type: PodMessageType.clear,
        source: PodId.fromInt(1),
        destination: PodId.fromInt(2),
        payload: Uint8List.fromList([9, 9]),
        sequenceNumber: 1,
      ));
      expect(link.received, hasLength(1));
    });

    /// A pending request-to-send is not noise: the pod has something to say, and
    /// talking over it would desynchronise both sides.
    test('a pending request-to-send still stops a send', () async {
      final link = FakePodLink(onMessage: (_) async => null);
      link.seedControl(PodControlWord.requestToSend.frame);
      expect(
        () => PodMessageIo(link).sendMessage(MessagePacket(
          type: PodMessageType.clear,
          source: PodId.fromInt(1),
          destination: PodId.fromInt(2),
          payload: Uint8List.fromList([1]),
          sequenceNumber: 1,
        )),
        throwsA(isA<PodLinkException>()),
      );
    });

    test('a pod that never answers reads as no message, not as a hang', () async {
      final link = FakePodLink(onMessage: (_) async => null);
      expect(await PodMessageIo(link).receiveMessage(), isNull);
    });
  });

  group('pairing against a pod that computes its own key', () {
    late PodSideKeyExchange pod;
    late PodPairing pairing;
    late FakePodLink link;
    late List<Uint8List> derivedKeys;

    setUp(() {
      derivedKeys = <Uint8List>[];
      pod = PodSideKeyExchange(
        privateKey: x25519GeneratePrivateKey(),
        nonce: hex('0f1e2d3c4b5a69788796a5b4c3d2e1f0'),
      );
      link = FakePodLink(onMessage: (request) async {
        final payload = request.payload;
        final text = String.fromCharCodes(payload.take(8));
        if (text.startsWith('SP1=')) {
          return null;
        }
        if (text.startsWith('SPS1=')) {
          pod.accept(const PodKeyedPayload(['SPS1=']).decode(payload).first);
          return request.withPayload(const PodKeyedPayload(['SPS1='])
              .encode([Uint8List.fromList(pod.publicKey + pod.nonce)]));
        }
        if (text.startsWith('SPS2=')) {
          return request.withPayload(
              const PodKeyedPayload(['SPS2=']).encode([pod.podConfirmation]));
        }
        return request.withPayload(const PodKeyedPayload(['P0='])
            .encode([Uint8List.fromList([0xa5])]));
      });
      pairing = PodPairing(
        messageIo: PodMessageIo(link),
        addresses: const PodAddressPair(podUniqueId: null),
        onKeyDerived: (key) async => derivedKeys.add(key),
      );
    });

    test('both sides arrive at the same long-term key', () async {
      final result = await pairing.negotiate();
      expect(toHex(result.longTermKey), toHex(pod.longTermKey));
      expect(result.longTermKey.length, 16);
    });

    test('the controller sends its confirmation value, and the pod agrees', () async {
      await pairing.negotiate();
      final sps2 = link.received.firstWhere((message) =>
          String.fromCharCodes(message.payload.take(5)) == 'SPS2=');
      final sent = const PodKeyedPayload(['SPS2=']).decode(sps2.payload).first;
      expect(toHex(sent), toHex(pod.controllerConfirmation));
    });

    test('the pairing messages are numbered 1 to 4 in order', () async {
      await pairing.negotiate();
      expect(link.received.map((message) => message.sequenceNumber), [1, 2, 3, 4]);
      expect(link.received.every((message) => message.type == PodMessageType.pairing),
          isTrue);
    });

    test('a pod confirmation that does not match aborts the pairing', () async {
      final tampering = FakePodLink(onMessage: (request) async {
        final text = String.fromCharCodes(request.payload.take(8));
        if (text.startsWith('SP1=')) {
          return null;
        }
        if (text.startsWith('SPS1=')) {
          pod.accept(const PodKeyedPayload(['SPS1=']).decode(request.payload).first);
          return request.withPayload(const PodKeyedPayload(['SPS1='])
              .encode([Uint8List.fromList(pod.publicKey + pod.nonce)]));
        }
        final wrong = Uint8List.fromList(pod.podConfirmation)..[0] ^= 0xFF;
        return request
            .withPayload(const PodKeyedPayload(['SPS2=']).encode([wrong]));
      });
      final attempt = PodPairing(
        messageIo: PodMessageIo(tampering),
        addresses: const PodAddressPair(podUniqueId: null),
        onKeyDerived: (key) async => derivedKeys.add(key),
      );
      expect(attempt.negotiate, throwsA(isA<PodPairingException>()));
    });

    /// The scenario that costs a pod: our confirmation reaches the pod, the pod
    /// keeps the key, and ITS confirmation is lost on the way back. The key must
    /// survive that, or the pod can never be addressed again by anyone.
    test('a confirmation lost on the way back still leaves us the key', () async {
      final losesLastReply = FakePodLink(onMessage: (request) async {
        final text = String.fromCharCodes(request.payload.take(8));
        if (text.startsWith('SP1=')) {
          return null;
        }
        if (text.startsWith('SPS1=')) {
          pod.accept(const PodKeyedPayload(['SPS1=']).decode(request.payload).first);
          return request.withPayload(const PodKeyedPayload(['SPS1='])
              .encode([Uint8List.fromList(pod.publicKey + pod.nonce)]));
        }
        // The pod received our confirmation and kept the key, but says nothing.
        return null;
      });
      final keys = <Uint8List>[];
      final attempt = PodPairing(
        messageIo: PodMessageIo(losesLastReply),
        addresses: const PodAddressPair(podUniqueId: null),
        onKeyDerived: (key) async => keys.add(key),
      );

      await expectLater(attempt.negotiate, throwsA(isA<PodPairingException>()));

      expect(keys, hasLength(1), reason: 'the key must be handed out before the send');
      expect(toHex(keys.single), toHex(pod.longTermKey),
          reason: 'and it must be the key the pod actually kept');
    });

    test('the key is handed out before our confirmation is sent', () async {
      final order = <String>[];
      final observing = FakePodLink(onMessage: (request) async {
        final text = String.fromCharCodes(request.payload.take(8));
        if (text.startsWith('SPS2=')) {
          order.add('sent confirmation');
          return request.withPayload(
              const PodKeyedPayload(['SPS2=']).encode([pod.podConfirmation]));
        }
        if (text.startsWith('SPS1=')) {
          pod.accept(const PodKeyedPayload(['SPS1=']).decode(request.payload).first);
          return request.withPayload(const PodKeyedPayload(['SPS1='])
              .encode([Uint8List.fromList(pod.publicKey + pod.nonce)]));
        }
        if (text.startsWith('SP1=')) {
          return null;
        }
        return request.withPayload(const PodKeyedPayload(['P0='])
            .encode([Uint8List.fromList([0xa5])]));
      });
      await PodPairing(
        messageIo: PodMessageIo(observing),
        addresses: const PodAddressPair(podUniqueId: null),
        onKeyDerived: (_) async => order.add('stored key'),
      ).negotiate();

      expect(order.first, 'stored key');
    });

    /// A mismatch is the one failure that PROVES the key is worthless, so it is
    /// reported as its own type — the caller discards only on this.
    test('a mismatch is distinguishable from every other failure', () async {
      final tampering = FakePodLink(onMessage: (request) async {
        final text = String.fromCharCodes(request.payload.take(8));
        if (text.startsWith('SP1=')) {
          return null;
        }
        if (text.startsWith('SPS1=')) {
          pod.accept(const PodKeyedPayload(['SPS1=']).decode(request.payload).first);
          return request.withPayload(const PodKeyedPayload(['SPS1='])
              .encode([Uint8List.fromList(pod.publicKey + pod.nonce)]));
        }
        final wrong = Uint8List.fromList(pod.podConfirmation)..[0] ^= 0xFF;
        return request
            .withPayload(const PodKeyedPayload(['SPS2=']).encode([wrong]));
      });
      final attempt = PodPairing(
        messageIo: PodMessageIo(tampering),
        addresses: const PodAddressPair(podUniqueId: null),
        onKeyDerived: (_) async {},
      );
      await expectLater(attempt.negotiate, throwsA(isA<PodPairingMismatch>()));
    });

    test('a pod that goes silent mid-pairing fails rather than inventing a key', () async {
      final silent = FakePodLink(onMessage: (_) async => null);
      final attempt = PodPairing(
        messageIo: PodMessageIo(silent),
        addresses: const PodAddressPair(podUniqueId: null),
        onKeyDerived: (key) async => derivedKeys.add(key),
      );
      expect(attempt.negotiate, throwsA(isA<PodPairingException>()));
    });
  });

  group('session establishment', skip: installOmnipodVendorKeys(), () {
    final longTermKey = hex('c0772899720972a314f557de66d571dd');
    const addresses = PodAddressPair(podUniqueId: 136326825);
    final podNonceHalf = hex('a1b2c3d4');

    FakePodLink podAnswering({required int eapSequence, bool wrongRes = false}) {
      return FakePodLink(onMessage: (request) async {
        final challenge = PodEapMessage.parse(request.payload);
        if (challenge.code == PodEapCode.success) {
          return null;
        }
        final random = challenge.attributes
            .firstWhere((attribute) => attribute.type == PodEapAttributeType.rand)
            .payload;
        final expected = Milenage(
          key: longTermKey,
          sqn: Uint8List.fromList([0, 0, 0, 0, eapSequence >> 8, eapSequence & 0xFF]),
          rand: random,
        ).res;
        final answer = wrongRes
            ? (Uint8List.fromList(expected)..[0] ^= 0xFF)
            : expected;
        return request.withPayload(PodEapMessage(
          code: PodEapCode.response,
          identifier: challenge.identifier,
          subType: PodEapMessage.subTypeChallenge,
          attributes: [
            PodEapAttribute(PodEapAttributeType.res, answer),
            PodEapAttribute(PodEapAttributeType.customIv, podNonceHalf),
          ],
        ).toBytes());
      });
    }

    test('agrees on a confidentiality key and a shared nonce', () async {
      final link = podAnswering(eapSequence: 2);
      final keys = await PodSessionEstablisher(
        messageIo: PodMessageIo(link),
        addresses: addresses,
        longTermKey: longTermKey,
        eapSequence: 2,
        messageSequence: 4,
        controllerNonceHalf: hex('11223344'),
        challengeRandom: hex('c2cd1248451103bd77a6c7ef88c441ba'),
        identifier: 0xbd,
      ).establish();

      expect(toHex(keys.confidentialityKey), '55799fd26664cbf6e476525e2dee52c6');
      expect(toHex(keys.nonce.prefix), '11223344a1b2c3d4');
      expect(keys.messageSequence, 6);
    });

    test('a pod that fails the challenge is rejected, not trusted', () async {
      final link = podAnswering(eapSequence: 2, wrongRes: true);
      final establisher = PodSessionEstablisher(
        messageIo: PodMessageIo(link),
        addresses: addresses,
        longTermKey: longTermKey,
        eapSequence: 2,
        messageSequence: 4,
      );
      expect(establisher.establish, throwsA(isA<PodSessionException>()));
    });

    test('a silent pod fails the handshake', () async {
      final establisher = PodSessionEstablisher(
        messageIo: PodMessageIo(FakePodLink(onMessage: (_) async => null)),
        addresses: addresses,
        longTermKey: longTermKey,
        eapSequence: 2,
        messageSequence: 4,
      );
      expect(establisher.establish, throwsA(isA<PodSessionException>()));
    });
  });

  group('PodSession reading a real encrypted pod reply', () {
    // The captured status reply, with the session key and nonce it was sent
    // under. Source address 0x08202ea9 is the pod that sent it.
    final captured = hex(
      '545711a10c16030008202ea908202ea8347cb97b385d45a3c40e404c55715ef3'
      'c3865017367e623c7d0b469e81cdfd9a',
    );

    PodSession sessionFor(FakePodLink link, {int podUniqueId = 136326825}) {
      return PodSession(
        messageIo: PodMessageIo(link),
        addresses: PodAddressPair(podUniqueId: podUniqueId),
        keys: PodSessionKeys(
          confidentialityKey: hex('55799fd26664cbf6e476525e2dee52c6'),
          nonce: SessionNonce(prefix: hex('6cff5d18b7616cae'), sequence: 22),
          messageSequence: 0,
          eapSequence: 2,
        ),
      );
    }

    test('decodes the captured reply into a pod status and acknowledges it', () async {
      final link = FakePodLink(onMessage: (_) async => null);
      final session = sessionFor(link);
      link.queueUnsolicited(MessagePacket.parse(captured));

      final response = await session.readAndAcknowledge();

      expect(response, isA<PodStatusResponse>());
      final status = response as PodStatusResponse;
      expect(status.reservoirPulsesRemaining, 1023);
      expect(status.reservoirUnits, isNull);
      expect(status.totalPulsesDelivered, 45);
      expect(status.minutesSinceActivation, 2);
      expect(status.lifecycle, PodLifecycleStatus.clutchDriveEngaged);
      expect(status.delivery, PodDeliveryStatus.suspended);
      // The acknowledgement went out, addressed to the reply it answers.
      expect(link.received, hasLength(1));
      expect(link.received.single.ack, isTrue);
      expect(link.received.single.ackNumber, 13);
    });

    test('a reply naming a different pod is refused', () async {
      final link = FakePodLink(onMessage: (_) async => null);
      final session = sessionFor(link, podUniqueId: 99999);
      link.queueUnsolicited(MessagePacket.parse(captured));
      expect(session.readAndAcknowledge, throwsA(isA<PodResponseException>()));
    });

    test('a reply whose tag does not verify never reaches the parser', () async {
      final tampered = Uint8List.fromList(captured)..[40] ^= 0xFF;
      final link = FakePodLink(onMessage: (_) async => null);
      final session = sessionFor(link);
      link.queueUnsolicited(MessagePacket.parse(tampered));
      expect(session.readAndAcknowledge, throwsA(isA<PodDecryptException>()));
    });
  });
}
