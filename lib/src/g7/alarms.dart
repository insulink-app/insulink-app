import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../profile/profile_glucose_state.dart';
import '../profile/profile_silent_state.dart';
import 'store.dart';

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
    const android = AndroidInitializationSettings('notification');
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
    // Track the zone even while silent, so the alarm doesn't fire on the FIRST
    // reading after silent mode is switched off if glucose is still in-zone —
    // only on a fresh crossing. Read the flag fresh so a toggle takes effect
    // without restarting the service isolate.
    if (level == _last) return;
    _last = level;
    if (level == G7AlarmLevel.none) return;
    if (await ProfileSilentState.load()) return;

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

  /// Notification id for the sensor-expiry warning (kept clear of the glucose
  /// alarm ids, which use [G7AlarmLevel.index] 0–4).
  static const _expiryId = 100;

  /// Fire a one-shot "sensor expires soon" warning once less than 24 h of the
  /// session remains. Persisted per-sensor in [store] so it fires only once per
  /// sensor, even across service/app restarts.
  Future<void> checkExpiry({
    required G7Store store,
    required String key,
    required int? sessionLengthSec,
    required int secsSinceStart,
  }) async {
    if (key.isEmpty || sessionLengthSec == null) return;
    final remaining = sessionLengthSec - secsSinceStart;
    // Only within the final 24 h, and not after it has already expired.
    if (remaining <= 0 || remaining > 86400) return;
    // Suppress while silent WITHOUT marking it notified, so the one-shot warning
    // still fires once silent mode is turned off (if there's time left).
    if (await ProfileSilentState.load()) return;
    if (store.expiryNotified(key)) return;
    await store.setExpiryNotified(key);

    final hours = (remaining / 3600).ceil();
    await _plugin.show(
      id: _expiryId,
      title: 'Sensor läuft bald ab',
      body: 'Dein Sensor läuft in etwa $hours h ab. Bereite einen neuen vor.',
      notificationDetails: const NotificationDetails(android: _channelWarning),
    );
  }
}
