import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_response_reader.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

void main() {
  group('PodAlarmStatusResponse decodes the captured alarm page', () {
    final captured = hex('021602080100000501BD00000003FF01950000000000670A');

    test('reads the routine fields', () {
      final status = PodAlarmStatusResponse(captured);
      expect(status.lifecycle, PodLifecycleStatus.runningAboveMinimumVolume);
      expect(status.delivery, PodDeliveryStatus.basalActive);
      expect(status.bolusPulsesRemaining, 0);
      expect(status.lastProgrammingSequenceNumber, 5);
      expect(status.totalPulsesDelivered, 445);
      expect(status.totalUnitsDelivered, closeTo(22.25, 1e-9));
      expect(status.reservoirPulsesRemaining, 1023);
      expect(status.reservoirUnits, isNull);
      expect(status.minutesSinceActivation, 405);
      expect(status.activeAlerts, isEmpty);
    });

    test('reads the alarm fields', () {
      final status = PodAlarmStatusResponse(captured);
      expect(status.alarm.rawCode, 0x00);
      expect(status.alarm.isAlarming, isFalse);
      expect(status.alarm.kind, PodAlarmKind.none);
      expect(status.minutesSinceAlarm, 0);
      expect(status.occlusionAlarm, isFalse);
      expect(status.pulseInfoInvalid, isFalse);
      expect(status.lifecycleWhenAlarmOccurred, PodLifecycleStatus.uninitialized);
      expect(status.bolusActiveWhenAlarmOccurred, isFalse);
      expect(status.occlusionType, 0);
      expect(status.rssi, 0);
    });

    test('the dispatcher routes the page to this parser', () {
      expect(PodResponseReader(captured).response, isA<PodAlarmStatusResponse>());
    });

    test('a truncated page is refused rather than half-read', () {
      expect(() => PodAlarmStatusResponse(captured.sublist(0, 20)),
          throwsA(isA<PodResponseException>()));
    });
  });

  group('an alarm mid-bolus reports what the body did not get', () {
    /// The captured page with an occlusion alarm, 40 bolus pulses still queued,
    /// and the bolus-active flag set.
    Uint8List occludedMidBolus() {
      final body = Uint8List.fromList(
          hex('021602080100000501BD00000003FF01950000000000670A'));
      body[5] = 0x00;
      body[6] = 0x28; // 40 pulses still to deliver
      body[10] = 0x14; // ALARM_OCCLUDED
      body[18] = 0x01; // occlusion flag
      body[19] = 0x18; // bolus was active, pod was running
      return body;
    }

    test('names the occlusion and the undelivered insulin', () {
      final status = PodAlarmStatusResponse(occludedMidBolus());
      expect(status.alarm.kind, PodAlarmKind.occlusion);
      expect(status.alarm.isAlarming, isTrue);
      expect(status.alarm.stopsDelivery, isTrue);
      expect(status.occlusionAlarm, isTrue);
      expect(status.bolusActiveWhenAlarmOccurred, isTrue);
      expect(status.undeliveredBolusUnits, closeTo(2.0, 1e-9));
    });
  });

  group('PodAlarm classifies the codes that lead to different advice', () {
    test('no alarm', () {
      expect(const PodAlarm(0x00).kind, PodAlarmKind.none);
      expect(const PodAlarm(0x00).isAlarming, isFalse);
    });

    test('occlusion, including the detection family', () {
      expect(const PodAlarm(0x14).kind, PodAlarmKind.occlusion);
      expect(const PodAlarm(0x57).kind, PodAlarmKind.occlusion);
      expect(const PodAlarm(0x6a).kind, PodAlarmKind.occlusion);
    });

    test('empty reservoir and expiry are their own cases', () {
      expect(const PodAlarm(0x18).kind, PodAlarmKind.emptyReservoir);
      expect(const PodAlarm(0x1c).kind, PodAlarmKind.expired);
    });

    test('over- and under-infusion form one safety-relevant class', () {
      for (final code in [0x80, 0x84, 0x88, 0x8a]) {
        expect(PodAlarm(code).kind, PodAlarmKind.infusionError,
            reason: 'code 0x${code.toRadixString(16)}');
      }
    });

    test('an escalated alert is distinguished from a fault', () {
      expect(const PodAlarm(0x29).kind, PodAlarmKind.escalatedAlert);
      expect(const PodAlarm(0x30).kind, PodAlarmKind.escalatedAlert);
    });

    test('radio alarms are their own class', () {
      expect(const PodAlarm(0xa0).kind, PodAlarmKind.communication);
      expect(const PodAlarm(0xc2).kind, PodAlarmKind.communication);
    });

    test('anything else is an internal fault, and keeps its raw code', () {
      final fault = const PodAlarm(0x33);
      expect(fault.kind, PodAlarmKind.internalFault);
      expect(fault.rawCode, 0x33);
      expect(fault.toString(), contains('0x33'));
    });

    test('every code from 0x01 to 0xff classifies as something actionable', () {
      for (var code = 0x01; code <= 0xff; code++) {
        final alarm = PodAlarm(code);
        expect(alarm.kind, isNot(PodAlarmKind.none),
            reason: 'code 0x${code.toRadixString(16)} read as no alarm');
        expect(alarm.stopsDelivery, isTrue);
      }
    });
  });
}
