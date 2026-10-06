import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:provider/provider.dart';

/// Which devices currently need the user, read in one place so the header's
/// devices button and the rows on the devices page always agree on it: a red
/// dot on the button is always explained by a red dot on the device behind it.
///
/// - **Sensor:** none is paired.
/// - **Pump:** the paired pod reports active alerts (the same ones the
///   overview's pod warnings show).
/// - **Google Health:** connecting failed and is still unresolved.
class DeviceAttention {
  /// Watches the device states, so the caller rebuilds when one changes.
  DeviceAttention.of(BuildContext context) {
    final pod = context.watch<PodController>();
    sensor = !context.watch<CgmController>().hasSensor;
    pump = pod.hasPod && (pod.status?.activeAlerts.isNotEmpty ?? false);
    googleHealth = context.watch<GoogleHealthState>().connectFailure != null;
  }

  late final bool sensor;
  late final bool pump;
  late final bool googleHealth;

  bool get any => sensor || pump || googleHealth;
}
