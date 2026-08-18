import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/pump/protocol/string_prefix_codec.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

void main() {
  group('PodStatusResponse decodes captured statuses', () {
    test('basal running, reservoir not yet measurable', () {
      final status = PodStatusResponse(hex('1D1800A02800000463FF'));
      expect(status.lifecycle, PodLifecycleStatus.runningAboveMinimumVolume);
      expect(status.delivery, PodDeliveryStatus.basalActive);
      expect(status.totalPulsesDelivered, 320);
      expect(status.lastProgrammingSequenceNumber, 5);
      expect(status.bolusPulsesRemaining, 0);
      expect(status.activeAlerts, isEmpty);
      expect(status.minutesSinceActivation, 280);
      expect(status.reservoirPulsesRemaining, 1023);
      expect(status.reservoirUnits, isNull);
      expect(status.totalUnitsDelivered, 16.0);
    });

    test('below minimum volume, reservoir measurable', () {
      final status = PodStatusResponse(hex('1D1905281000004387D3039A'));
      expect(status.lifecycle, PodLifecycleStatus.runningBelowMinimumVolume);
      expect(status.delivery, PodDeliveryStatus.basalActive);
      expect(status.totalPulsesDelivered, 2640);
      expect(status.lastProgrammingSequenceNumber, 2);
      expect(status.minutesSinceActivation, 4321);
      expect(status.reservoirPulsesRemaining, 979);
      expect(status.reservoirUnits, closeTo(48.95, 1e-9));
    });

    test('bolus in progress', () {
      final status = PodStatusResponse(hex('1D180519C00E0039A7FF8085'));
      expect(status.lastProgrammingSequenceNumber, 8);
      expect(status.bolusPulsesRemaining, 14);
      expect(status.bolusUnitsRemaining, closeTo(0.7, 1e-9));
      expect(status.minutesSinceActivation, 3689);
      expect(status.totalPulsesDelivered, 2611);
    });

    test('an unrecognised delivery state reads as unknown, never as suspended', () {
      final status = PodStatusResponse(hex('1D990714201F0042ED8801DE'));
      expect(status.delivery, PodDeliveryStatus.unknown);
      expect(status.delivery.isSuspended, isFalse);
      expect(status.lifecycle, PodLifecycleStatus.runningBelowMinimumVolume);
      expect(status.bolusPulsesRemaining, 31);
      expect(status.reservoirPulsesRemaining, 392);
    });

    test('an active expiration alert is reported', () {
      final status = PodStatusResponse(hex('1D980559C820404393FF83AA'));
      expect(status.activeAlerts, {PodAlert.expiration});
      expect(status.minutesSinceActivation, 4324);
    });

    test('a truncated status is refused rather than half-read', () {
      expect(() => PodStatusResponse(hex('1D1800A0')),
          throwsA(isA<PodResponseException>()));
    });
  });

  group('PodNakResponse', () {
    test('decodes an illegal-parameter refusal', () {
      final nak = PodNakResponse(hex('0603070009'));
      expect(nak.error, PodNakError.illegalParameter);
      expect(nak.lifecycle, PodLifecycleStatus.runningBelowMinimumVolume);
      expect(nak.resyncCount, 0);
    });

    test('a security-code refusal carries a resync count, not a lifecycle', () {
      final nak = PodNakResponse(hex('0603140102'));
      expect(nak.error, PodNakError.illegalSecurityCode);
      expect(nak.resyncCount, 0x0102);
      expect(nak.lifecycle, isNull);
    });
  });

  group('PodKeyedPayload', () {
    test('round-trips the command envelope', () {
      const codec = PodKeyedPayload(['S0.0=', ',G0.0']);
      final body = hex('024200023C030E0100024C');
      final encoded = codec.encode([body, Uint8List(0)]);
      expect(codec.decode(encoded).first, body);
    });

    test('rejects a payload whose key does not match', () {
      const codec = PodKeyedPayload(['SPS1=']);
      expect(() => codec.decode(hex('535053323d0000')),
          throwsA(isA<PodKeyedPayloadException>()));
    });

    test('rejects a length longer than the payload carries', () {
      const codec = PodKeyedPayload(['SPS1=']);
      final truncated = Uint8List.fromList('SPS1='.codeUnits + [0x00, 0x40, 0x01]);
      expect(() => codec.decode(truncated),
          throwsA(isA<PodKeyedPayloadException>()));
    });
  });
}
