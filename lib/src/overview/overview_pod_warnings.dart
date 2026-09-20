import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/overview/overview_notice.dart';
import 'package:insulink/src/pump/service/pod_alarms.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

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

  Future<void> _read() async {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final warning in _standing) _card(warning),
      ],
    );
  }

  Widget _card(ActiveNotification warning) {
    final id = warning.id!;
    return OverviewNotice(
      dismissKey: 'pod-warning-$id',
      icon: PhosphorIconsBold.warning,
      title: warning.title,
      message: warning.body ?? '',
      onDismiss: () => _dismiss(id),
      onTap: () => openPumpPage(context),
    );
  }
}
