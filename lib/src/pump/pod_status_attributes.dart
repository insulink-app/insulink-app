import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/sensor/info/sensor_attributes.dart';

/// Turns a pod status into the labelled rows the device page shows, reusing the
/// sensor page's section layout so both device pages read the same.
///
/// Where the pod reports something it cannot measure — a reservoir above its
/// measuring range — the row says so in words. Formatting that sentinel as a
/// number would show a precise-looking figure that is not one.
class PodStatusAttributes {
  PodStatusAttributes({
    required this.status,
    required this.readAt,
    required this.localize,
  });

  final PodStatusResponse? status;
  final DateTime? readAt;
  final String Function(String key) localize;

  List<SensorSection> build() {
    final current = status;
    if (current == null) {
      return [
        (
          titleKey: 'pump.status._',
          items: [
            MapEntry(
              localize('pump.status.last_read'),
              localize('pump.status.never_read'),
            ),
          ],
        ),
      ];
    }
    return [
      (
        titleKey: 'pump.status._',
        items: [
          MapEntry(
            localize('pump.status.lifecycle'),
            _lifecycle(current.lifecycle),
          ),
          MapEntry(
            localize('pump.status.delivery'),
            _delivery(current.delivery),
          ),
          MapEntry(localize('pump.status.reservoir'), _reservoir(current)),
          MapEntry(localize('pump.status.age'), _duration(current.age)),
          MapEntry(
            localize('pump.status.alerts'),
            _alerts(current.activeAlerts),
          ),
          MapEntry(localize('pump.status.last_read'), _readAt()),
        ],
      ),
    ];
  }

  String _reservoir(PodStatusResponse current) {
    final units = current.reservoirUnits;
    if (units == null) {
      return localize('pump.status.reservoir_plenty');
    }
    return '${units.toStringAsFixed(2)} U';
  }

  String _duration(Duration age) {
    final hours = age.inHours;
    final minutes = age.inMinutes % 60;
    return '${hours}h ${minutes}min';
  }

  String _readAt() {
    final moment = readAt;
    if (moment == null) {
      return localize('pump.status.never_read');
    }
    final minutes = DateTime.now().difference(moment).inMinutes;
    return minutes < 1 ? '<1 min' : '$minutes min';
  }

  String _alerts(Set<PodAlert> alerts) {
    if (alerts.isEmpty) {
      return localize('pump.status.no_alerts');
    }
    return alerts.map((alert) => localize(_alertKey(alert))).join(', ');
  }

  String _lifecycle(PodLifecycleStatus lifecycle) {
    return localize(switch (lifecycle) {
      PodLifecycleStatus.filled => 'pump.lifecycle.filled',
      PodLifecycleStatus.uniqueIdSet => 'pump.lifecycle.uid_set',
      PodLifecycleStatus.priming => 'pump.lifecycle.priming',
      PodLifecycleStatus.basalProgramSet => 'pump.lifecycle.basal_set',
      PodLifecycleStatus.runningAboveMinimumVolume => 'pump.lifecycle.running',
      PodLifecycleStatus.runningBelowMinimumVolume =>
        'pump.lifecycle.running_low',
      PodLifecycleStatus.alarm => 'pump.lifecycle.alarm',
      PodLifecycleStatus.deactivated => 'pump.lifecycle.deactivated',
      _ => 'pump.lifecycle.unknown',
    });
  }

  String _delivery(PodDeliveryStatus delivery) {
    return localize(switch (delivery) {
      PodDeliveryStatus.suspended => 'pump.delivery.suspended',
      PodDeliveryStatus.basalActive => 'pump.delivery.basal',
      PodDeliveryStatus.tempBasalActive => 'pump.delivery.temp_basal',
      PodDeliveryStatus.priming => 'pump.delivery.priming',
      PodDeliveryStatus.bolusAndBasalActive => 'pump.delivery.bolus_basal',
      PodDeliveryStatus.bolusAndTempBasalActive => 'pump.delivery.bolus_temp',
      PodDeliveryStatus.unknown => 'pump.delivery.unknown',
    });
  }

  String _alertKey(PodAlert alert) {
    return switch (alert) {
      PodAlert.autoOff => 'pump.alert.auto_off',
      PodAlert.multiCommand => 'pump.alert.multi_command',
      PodAlert.expirationImminent => 'pump.alert.expiration_imminent',
      PodAlert.userSetExpiration => 'pump.alert.user_set_expiration',
      PodAlert.lowReservoir => 'pump.alert.low_reservoir',
      PodAlert.suspendInProgress => 'pump.alert.suspend_in_progress',
      PodAlert.suspendEnded => 'pump.alert.suspend_ended',
      PodAlert.expiration => 'pump.alert.expiration',
    };
  }
}
