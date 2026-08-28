import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/localization/service_strings.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';

/// The two notification channels the pod warnings use.
///
/// Split from [PodAlarmManager] so the decisions and the Android plumbing stay
/// apart — the decisions are what the tests exercise.
class PodAlarmChannels {
  final ServiceStrings _strings = ServiceStrings();

  /// The channel for a pod that has stopped delivering. Bypasses Do Not Disturb
  /// for the same reason the glucose alarms do: insulin has stopped, and the user
  /// finding out hours later is the harm being prevented.
  Future<AndroidNotificationDetails> urgent() async {
    return AndroidNotificationDetails(
      'insulink_pod_alarm',
      await _strings.get('alarm.channel.pod_alarm.name'),
      channelDescription: await _strings.get('alarm.channel.pod_alarm.desc'),
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      channelBypassDnd: true,
      vibrationPattern: Int64List.fromList(_vibrationPattern),
      enableVibration: true,
    );
  }

  /// The channel for the advance warnings, which are heads-ups rather than
  /// emergencies and so respect silent mode.
  Future<AndroidNotificationDetails> warning() async {
    final quiet = (await ProfileSilentState.load()).mutesSound;
    final slug = quiet ? 'warning_silent' : 'warning';
    return AndroidNotificationDetails(
      'insulink_alarm_$slug',
      await _strings.get('alarm.channel.$slug.name'),
      channelDescription: await _strings.get('alarm.channel.$slug.desc'),
      playSound: !quiet,
      importance: Importance.high,
      priority: Priority.high,
      vibrationPattern: Int64List.fromList(_vibrationPattern),
      enableVibration: true,
    );
  }

  static const List<int> _vibrationPattern = [0, 400, 200, 400];
}
