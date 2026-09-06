import 'package:flutter/widgets.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/status/connection_timeline.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Gathers what each device left behind into the rows the connection page draws.
///
/// Every source here is data the app already keeps for its own reasons — the
/// glucose archive, the intraday pulse archive, the pod's contact log — read at
/// minute resolution and handed to [ConnectionTimeline], which decides what
/// counts as a gap. Nothing new is recorded for this page except the pod's
/// contact log, and only because the pod is the one device that left no trace of
/// a link that worked.
class ConnectionStatusReader {
  const ConnectionStatusReader(this.context, this.timeline);

  final BuildContext context;
  final ConnectionTimeline timeline;

  Future<List<DeviceConnection>> read() async {
    final sensor = _sensor();
    final pod = await _pod();
    final band = await _band();
    return [sensor, pod, band];
  }

  /// The CGM, from the long-term glucose archive: a stored minute is a minute a
  /// reading arrived, which is the same thing as the link having worked.
  DeviceConnection _sensor() {
    final controller = context.read<CgmController>();
    final minutes = controller.archiveSince(timeline.window).keys;
    return DeviceConnection(
      labelKey: 'sensor.label',
      icon: PhosphorIconsFill.drop,
      lastContact: controller.lastUpdate,
      covered: timeline.cover(minutes),
    );
  }

  /// The pod, from [PodContactLog]. The store is re-read first: its getters come
  /// from a cache that is per isolate, and the contact log is written by the
  /// background service, so this isolate would otherwise draw whatever it knew
  /// when the app started.
  Future<DeviceConnection> _pod() async {
    final store = context.read<PodController>().store;
    await store.reload();
    return DeviceConnection(
      labelKey: 'pump.label',
      icon: PhosphorIconsFill.syringe,
      lastContact: store.lastSeenAt,
      covered: timeline.cover(store.contactMinutes),
    );
  }

  /// The Fitbit band, from the intraday pulse archive. A stored minute is a
  /// minute the band delivered a heartbeat, so the gaps are the stretches it was
  /// out of range, off the wrist, or held by something else.
  Future<DeviceConnection> _band() async {
    final samples = await const IntradayPulseStore().rangeCurve(
      timeline.start,
      timeline.now,
    );
    return DeviceConnection(
      labelKey: 'google_health.label',
      icon: PhosphorIconsBold.watch,
      lastContact: samples.isEmpty ? null : samples.last.at,
      covered: timeline.cover([
        for (final sample in samples)
          sample.at.millisecondsSinceEpoch ~/ 60000,
      ]),
    );
  }
}
