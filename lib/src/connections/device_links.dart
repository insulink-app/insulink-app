import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/device_attention.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:provider/provider.dart';

/// Where one connection stands: running, asking for the user, or not set up.
enum LinkState { active, attention, idle }

/// One connection as the connections page shows it: its state (the dot) and
/// the line under its name, the device or that none is paired.
class DeviceLink {
  const DeviceLink(this.state, this.detailKey);

  final LinkState state;
  final String detailKey;

  /// Counted in "x von y aktiv": set up, or asking for the user.
  bool get counted => state != LinkState.idle;
}

/// The three connections, read on top of [DeviceAttention] so the page and
/// the header's devices button agree on what needs the user.
///
/// A missing sensor is a problem (the app reads nothing without it); a pump
/// without a pod or an unconnected Google Health is simply not set up.
class DeviceLinks {
  DeviceLinks.of(BuildContext context) {
    final attention = DeviceAttention.of(context);
    final cgm = context.watch<CgmController>();
    final hasPod = context.watch<PodController>().hasPod;
    final health = context.watch<GoogleHealthState>().connected;
    sensor = cgm.hasSensor
        ? DeviceLink(LinkState.active, _sensorKey(cgm.sensorType))
        : const DeviceLink(LinkState.attention, 'connections.not_paired');
    pump = _link(
      hasPod,
      attention.pump,
      'pump.type.dash',
      'connections.not_paired',
    );
    googleHealth = _link(
      health,
      attention.googleHealth,
      'connections.band',
      'connections.not_connected',
    );
  }

  late final DeviceLink sensor;
  late final DeviceLink pump;
  late final DeviceLink googleHealth;

  List<DeviceLink> get all => [sensor, pump, googleHealth];

  int get activeCount =>
      all.where((link) => link.state == LinkState.active).length;
  int get attentionCount =>
      all.where((link) => link.state == LinkState.attention).length;
  int get countedCount => all.where((link) => link.counted).length;

  String _sensorKey(SensorType type) =>
      type == SensorType.abbottLibre3 ? 'sensor.type.libre3' : 'sensor.type.g7';

  DeviceLink _link(bool setUp, bool alarm, String deviceKey, String offKey) {
    if (alarm) {
      return DeviceLink(LinkState.attention, setUp ? deviceKey : offKey);
    }
    return setUp
        ? DeviceLink(LinkState.active, deviceKey)
        : DeviceLink(LinkState.idle, offKey);
  }
}
