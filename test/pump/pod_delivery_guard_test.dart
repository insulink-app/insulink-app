import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_bolus_command.dart';
import 'package:insulink/src/pump/protocol/pod_delivery_guard.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

Uint8List hex(String text) => Uint8List.fromList([
      for (var index = 0; index < text.length; index += 2)
        int.parse(text.substring(index, index + 2), radix: 16),
    ]);

void main() {
  // Running above minimum volume, basal active, reservoir reads "plenty".
  final running = PodStatusResponse(hex('1D1800A02800000463FF'));
  // Running, but with 14 bolus pulses still to deliver.
  final bolusing = PodStatusResponse(hex('1D580519C00E0039A7FF8085'));
  // Running below minimum volume with 979 pulses (48.95 U) left.
  final lowReservoir = PodStatusResponse(hex('1D1905281000004387D3039A'));

  const guard = PodDeliveryGuard(maxBolusUnits: 10.0, maxUnitsPerHour: 15.0);
  const fresh = Duration(seconds: 5);

  PodDeliveryDecision check(
    double units, {
    PodStatusResponse? status,
    Duration age = fresh,
    double lastHour = 0,
  }) {
    return guard.checkBolus(
      amount: PodBolusAmount.fromUnits(units),
      status: status ?? running,
      statusAge: age,
      deliveredLastHour: lastHour,
    );
  }

  test('allows a normal bolus on a healthy pod', () {
    expect(check(3.0).isAllowed, isTrue);
  });

  test('refuses a bolus above the user limit instead of clamping it', () {
    final decision = check(10.05);
    expect(decision.isAllowed, isFalse);
    expect(decision.refusal, PodDeliveryRefusal.aboveUserLimit);
  });

  test('allows a bolus exactly at the user limit', () {
    expect(check(10.0).isAllowed, isTrue);
  });

  test('refuses a bolus that would break the rolling hourly limit', () {
    expect(check(3.0, lastHour: 13.0).refusal, PodDeliveryRefusal.aboveHourlyLimit);
    expect(check(2.0, lastHour: 13.0).isAllowed, isTrue);
  });

  test('refuses to stack a second bolus while one is running', () {
    expect(bolusing.delivery.isBolusing, isTrue);
    expect(check(1.0, status: bolusing).refusal, PodDeliveryRefusal.alreadyBolusing);
  });

  test('refuses a bolus larger than the measured reservoir', () {
    expect(check(30.0, status: lowReservoir).isAllowed, isFalse);
    expect(check(10.0, status: lowReservoir).isAllowed, isTrue);
  });

  test('refuses to act on a stale pod status', () {
    expect(check(1.0, age: const Duration(minutes: 5)).refusal,
        PodDeliveryRefusal.statusTooOld);
  });

  test('the protocol ceiling still applies below a looser user limit', () {
    const loose = PodDeliveryGuard(maxBolusUnits: 50.0, maxUnitsPerHour: 100.0);
    expect(() => PodBolusAmount.fromUnits(40.0), throwsA(isA<PodDoseException>()));
    expect(
      loose.checkBolus(
        amount: PodBolusAmount.fromUnits(30.0),
        status: running,
        statusAge: fresh,
        deliveredLastHour: 0,
      ).isAllowed,
      isTrue,
    );
  });

  test('suspend stays available on a running pod', () {
    expect(guard.checkSuspend(status: running).isAllowed, isTrue);
    expect(guard.checkSuspend(status: lowReservoir).isAllowed, isTrue);
  });
}
