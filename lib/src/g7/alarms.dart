import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../profile/profile_glucose_state.dart';

/// Glucose alarm severity. Ordered so a transition between two non-`none`
/// levels (e.g. urgent low → warning low) still re-fires the notification.
enum G7AlarmLevel { none, lowWarning, lowUrgent, highWarning, highUrgent }

/// Watches live EGV readings and raises local notifications when glucose
/// crosses into a low/high zone. Runs inside the foreground-service isolate
/// (same place [G7TaskHandler] lives) so alarms fire even with the app closed.
class G7AlarmManager {
  G7AlarmManager(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  G7AlarmLevel _last = G7AlarmLevel.none;

  static const _channelWarning = AndroidNotificationDetails(
    'insulink_alarm_warning',
    'Zucker-Warnung',
    channelDescription: 'Leichte Warnung bei grenzwertigem Zuckerwert.',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _channelUrgent = AndroidNotificationDetails(
    'insulink_alarm_urgent',
    'Zucker-Alarm',
    channelDescription: 'Starker Alarm bei kritischem Zuckerwert.',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
  );

  /// Must be called once per isolate before [check] (mirrors `RustLib.init()`).
  static Future<void> init(FlutterLocalNotificationsPlugin plugin) async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
  }

  static G7AlarmLevel _levelFor(
    int mgdl,
    ({GlucoseUnit unit, int urgentLow, int low, int high, int urgentHigh}) t,
  ) {
    if (mgdl <= t.urgentLow) return G7AlarmLevel.lowUrgent;
    if (mgdl >= t.urgentHigh) return G7AlarmLevel.highUrgent;
    if (mgdl <= t.low) return G7AlarmLevel.lowWarning;
    if (mgdl >= t.high) return G7AlarmLevel.highWarning;
    return G7AlarmLevel.none;
  }

  /// Evaluate a new reading and notify on entering a different alarm zone.
  /// Re-evaluating the same zone repeatedly (e.g. every 5 min EGV) does not
  /// re-notify, so the alarm only fires again once the value has recovered
  /// and crossed back in, or escalated/de-escalated to a different zone.
  ///
  /// Thresholds + display unit are read fresh from storage each call so the
  /// user's profile changes take effect without restarting the service isolate.
  Future<void> check(int? mgdl, double trendPerMin) async {
    if (mgdl == null) return;
    final t = await ProfileGlucoseState.loadThresholds();
    final level = _levelFor(mgdl, t);
    if (level == _last) return;
    _last = level;
    if (level == G7AlarmLevel.none) return;

    // Format the value in the user's chosen unit for the notification text.
    final value = t.unit == GlucoseUnit.mmol
        ? '${(mgdl / 18.0182).toStringAsFixed(1)} ${t.unit.label}'
        : '$mgdl ${t.unit.label}';

    final String title;
    final String body;
    final AndroidNotificationDetails details;
    switch (level) {
      case G7AlarmLevel.lowWarning:
        title = 'Zucker niedrig';
        body = value;
        details = _channelWarning;
      case G7AlarmLevel.lowUrgent:
        title = '⚠️ Zucker SEHR niedrig';
        body = value;
        details = _channelUrgent;
      case G7AlarmLevel.highWarning:
        title = 'Zucker hoch';
        body = value;
        details = _channelWarning;
      case G7AlarmLevel.highUrgent:
        title = '⚠️ Zucker SEHR hoch';
        body = value;
        details = _channelUrgent;
      case G7AlarmLevel.none:
        return;
    }
    await _plugin.show(
      id: level.index,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
    );
  }
}
