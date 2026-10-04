import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/pod_warning_card.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:insulink/src/pump/service/pod_alarms.dart';
import 'package:insulink/src/pump/service/pod_warning_kind.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The pod warnings the background service has raised, repeated on the overview.
///
/// A notification is easy to miss: it arrives while the phone is in a pocket,
/// and it is gone the moment anything else in the shade is cleared with it. A
/// pod that has stopped delivering, or that expires tonight, has to be legible
/// on the screen the user actually opens.
///
/// It mirrors the shade rather than keeping its own list, which is what makes
/// acknowledging work in both directions: a notification tapped or swiped away
/// is no longer standing, so the card goes with it, and a card swiped away
/// cancels the notification.
///
/// Tapping opens the pump page, because every one of these warnings is about
/// something to check on the pod.
class OverviewPodWarnings extends StatefulWidget {
  const OverviewPodWarnings({super.key});

  @override
  State<OverviewPodWarnings> createState() => _OverviewPodWarningsState();
}

class _OverviewPodWarningsState extends State<OverviewPodWarnings>
    with WidgetsBindingObserver {
  /// How often the shade is re-read while the overview is on screen. The
  /// warnings are raised from a poll a quarter of an hour apart, so this only
  /// has to be quick enough that one arriving while the user is looking at the
  /// page does not feel late.
  // ponytail: a poll, because the plugin reports a dismissal only to a callback
  // in another isolate. Swap for that callback if the interval ever matters.
  static const Duration _pollInterval = Duration(seconds: 30);

  final PodAlarmManager _alarms = PodAlarmManager(
    FlutterLocalNotificationsPlugin(),
  );

  List<ActiveNotification> _standing = const [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollInterval, (_) => _read());
    _read();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A resume is when the shade has most likely changed: the user came back from
  /// the notification they just acted on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _read();
    }
  }

  /// Re-reads the shade, and the pod status the background poll left behind so
  /// the card shows an alert found while the app was closed.
  Future<void> _read() async {
    unawaited(context.read<PodController>().adoptBackgroundStatus());
    final standing = await _alarms.standingWarnings();
    if (mounted) {
      setState(() => _standing = standing);
    }
  }

  Future<void> _dismiss(int id) async {
    setState(() {
      _standing = [
        for (final warning in _standing)
          if (warning.id != id) warning,
      ];
    });
    await _alarms.dismissWarning(id);
  }

  /// The status time the pod's own alerts were swiped away at. They stay
  /// hidden until a newer status arrives, so an alert the pod still reports
  /// after the acknowledgement comes back.
  DateTime? _alertsDismissedAt;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    return PodWarningCard(
      lines: [
        ?_alertsLine(controller),
        for (final warning in _standing) _line(warning),
      ],
      onOpen: () => openPumpPage(context),
    );
  }

  /// The alerts the pod itself is beeping about, with the button that silences
  /// them. Not the shade: the pod's alert bits from the last status anyone read,
  /// the background poll's included.
  PodWarningLine? _alertsLine(PodController controller) {
    final alerts = controller.status?.activeAlerts ?? const {};
    final hidden =
        _alertsDismissedAt != null &&
        _alertsDismissedAt == controller.statusReadAt;
    if (!controller.hasPod || alerts.isEmpty || hidden) {
      return null;
    }
    return PodWarningLine(
      dismissKey: 'pod-alerts-${controller.statusReadAt}',
      icon: PhosphorIconsBold.bellRinging,
      title: Locales.string(context, 'overview.pod_alerts'),
      message: alerts
          .map(
            (alert) => Locales.string(context, 'pump.alert.${alert.localeKey}'),
          )
          .join(', '),
      critical: false,
      onDismiss: () => _acknowledgeAlerts(controller),
      action: const PodSilenceAlertsButton(),
    );
  }

  void _acknowledgeAlerts(PodController controller) {
    setState(() => _alertsDismissedAt = controller.statusReadAt);
    controller.silenceAlerts();
  }

  PodWarningLine _line(ActiveNotification warning) {
    final id = warning.id!;
    final kind = PodWarningKind.values.firstWhere((kind) => kind.id == id);
    return PodWarningLine(
      dismissKey: 'pod-warning-$id',
      icon: kind.icon,
      title: warning.title ?? '',
      message: warning.body ?? '',
      critical: kind.critical,
      onDismiss: () => _dismiss(id),
    );
  }
}

/// The glyph each warning is told apart by at a glance.
extension on PodWarningKind {
  IconData get icon => switch (this) {
    PodWarningKind.expiry => PhosphorIconsBold.hourglassMedium,
    PodWarningKind.expired => PhosphorIconsBold.hourglassHigh,
    PodWarningKind.reservoir => PhosphorIconsBold.drop,
    PodWarningKind.alarm => PhosphorIconsBold.siren,
    PodWarningKind.unreachable => PhosphorIconsBold.bluetoothSlash,
    PodWarningKind.stopped => PhosphorIconsBold.stopCircle,
    PodWarningKind.loopStopped => PhosphorIconsBold.pauseCircle,
  };
}
