import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// Closes the basal accounting window: books what the pod delivered since the
/// last booking and moves the mark forward.
///
/// Shared by the background watch and the automation because both have to do it
/// and neither may skip it. It matters most to the automation, which REPLACES the
/// temporary rate every cycle: the store holds one temporary rate at a time, so a
/// window that is still open when the rate is replaced would be billed at the new
/// rate rather than the one that ran. Booking first is what keeps an automated
/// log honest.
class PodBasalBooking {
  const PodBasalBooking(this.store, {this.now = DateTime.now});

  final PodStore store;
  final DateTime Function() now;

  /// Insulin delivered in the window ABOVE what the schedule alone would have
  /// given, which is what the automation added.
  ///
  /// Never negative: a window below the schedule withheld background insulin,
  /// which is not extra insulin having been given.
  double _excessOver(
    List<double> rates,
    DateTime from,
    DateTime to,
    double delivered,
  ) {
    final scheduled = PodBasalDelivery(rates).unitsBetween(from, to);
    final excess = delivered - scheduled;
    return excess > 0 ? excess : 0;
  }

  /// Books the window that has passed and returns the units, or null when there
  /// was nothing to book.
  ///
  /// Gated on the pod reporting that it is actually delivering: a suspended or
  /// alarming pod books a zero and still closes its window, so the next booking
  /// cannot claim the stretch as if insulin had been running through it.
  ///
  /// **A known schedule with no accounting mark opens one here**, rather than
  /// booking nothing forever. Only the activation wizard used to open the mark,
  /// so every other way a schedule reaches the store — a pod adopted from the
  /// account and then sent the profile, a schedule reprogrammed on a pod whose
  /// mark was cleared — left the ledger permanently shut. Nothing was booked,
  /// which emptied the insulin chart, the pump history and the samples the
  /// account gets, with no way back short of a pod change.
  Future<double?> book(PodStatusResponse status) async {
    final rates = store.basalRates;
    if (rates == null) {
      return null;
    }
    final countedTo = store.basalCountedTo;
    if (countedTo == null) {
      await store.startBasalAccounting(now());
      return null;
    }
    final until = now();
    if (!until.isAfter(countedTo)) {
      return null;
    }
    if (!status.delivery.isBasalRunning && !status.delivery.isTempBasalRunning) {
      await store.addBasalDelivery(at: until, units: 0, countedTo: until);
      return 0;
    }
    final temporary = store.temporaryBasal;
    final units = PodBasalDelivery(rates, temporary: temporary)
        .unitsBetween(countedTo, until);
    await store.addBasalDelivery(at: until, units: units, countedTo: until);
    await store.recordAutomationExcess(
      until,
      _excessOver(rates, countedTo, until, units),
    );
    if (temporary != null && !until.isBefore(temporary.end)) {
      await store.clearTemporaryBasal();
    }
    return units;
  }
}
