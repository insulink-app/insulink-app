import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/cgm/service/alarms.dart';

/// A tap on the BODY of the "training detected" notification: the user wants to
/// see what was detected, not to confirm or reject it blind. The two buttons on
/// that notification keep doing what they did.
///
/// Deliberately UI-free, so `alarms.dart` (which runs in the service isolate)
/// can hand a tap over without dragging the page layer in. Who pushes what is
/// decided in `main.dart`, the only place that holds both the navigator and the
/// training state.
class DetectedTrainingTap {
  /// The training a tap asked for, or null once it has been shown.
  ///
  /// A notifier rather than a return value: the tap lands in a top-level
  /// notification callback that has no widget tree to hand it to, and possibly
  /// before there is one at all.
  static final ValueNotifier<String?> requested = ValueNotifier(null);

  /// Take the training id out of the notification payload ("id\nwritablePath",
  /// see `G7AlarmManager.notifyTrainingDetected`).
  static void record(String? payload) {
    final id = (payload ?? '').split('\n').first;
    if (id.isNotEmpty) {
      requested.value = id;
    }
  }

  /// Register THIS isolate for notification taps and adopt one that launched
  /// the app.
  ///
  /// Both halves are needed and neither covers the other: the callback only
  /// reaches the isolate that registered it on the app's own engine (the
  /// service isolate's registration answers a different one), and an app that
  /// was not running when the notification was tapped is started fresh, with
  /// the tap waiting in the launch details instead.
  static Future<void> start() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await G7AlarmManager(plugin).init();
    final launch = await plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp != true ||
        response?.id != G7AlarmManager.trainingDetectedId ||
        response?.actionId != null) {
      return;
    }
    record(response?.payload);
  }
}
