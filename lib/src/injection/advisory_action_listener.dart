import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/cgm/service/advisory_action.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:insulink/src/injection/advisory_countermeasure.dart';

/// Answers the pre-warning notification's countermeasure buttons.
///
/// Sits inside the provider tree because that is what the work needs: the meal
/// log, the pod and the user's bolus settings all live here (see
/// [AdvisoryCountermeasure]).
///
/// Android delivers such a tap two different ways and both have to be picked up:
/// a RUNNING app gets it through the plugin's response callback, while a tap
/// that STARTED the app has already happened by the time anything can listen, so
/// the plugin holds that one in the launch details instead. Reading only the
/// first is the same as doing nothing whenever the app was closed, which is most
/// of the time a pre-warning fires.
class AdvisoryActionListener extends StatefulWidget {
  const AdvisoryActionListener({super.key, required this.child});

  final Widget child;

  @override
  State<AdvisoryActionListener> createState() => _AdvisoryActionListenerState();
}

class _AdvisoryActionListenerState extends State<AdvisoryActionListener> {
  /// The payload already acted on, so a tap cannot be carried out twice.
  ///
  /// The launch details keep reporting the intent that started the activity, and
  /// the callback fires for the same tap while the app is warm. A duplicate meal
  /// would be a nuisance; a duplicate dose would not be.
  String? _handled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  Future<void> _listen() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await G7AlarmManager(plugin).init(onResponse: _onResponse);
    final launch = await plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (response != null && (launch?.didNotificationLaunchApp ?? false)) {
      _onResponse(response);
    }
  }

  void _onResponse(NotificationResponse response) {
    final request = AdvisoryRequest.parse(response.actionId, response.payload);
    final key = '${response.actionId}\n${response.payload}';
    if (request == null || _handled == key || !mounted) {
      return;
    }
    _handled = key;
    unawaited(AdvisoryCountermeasure(context).run(request));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
