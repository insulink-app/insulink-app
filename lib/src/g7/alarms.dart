import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../profile/profile_connection_state.dart';
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

  // The alarm TONE is played manually through the ALARM audio stream (see
  // [_playSound]) — NOT via the notification channel. Channel sounds proved
  // unreliable in practice (they obey the notification-volume slider, which can
  // be 0, and the channel's sound/routing is frozen at creation). Playing it
  // ourselves with usage=alarm makes it obey the alarm-volume slider instead and
  // sound through silenced ringer / DnD / screen off, like Dexcom does. So these
  // channels are SILENT (`playSound: false`); they only carry the visual heads-up
  // and the urgent full-screen intent. `channelBypassDnd` still lets the visual
  // alert through DnD.
  static final AudioPlayer _player = AudioPlayer(playerId: 'insulink_alarm');

  static const _channelLowWarning = AndroidNotificationDetails(
    'insulink_alarm_low_warning',
    'Zucker niedrig — Warnung',
    channelDescription: 'Warnung bei niedrigem Zuckerwert.',
    importance: Importance.high,
    priority: Priority.high,
    playSound: false,
    channelBypassDnd: true,
  );

  static const _channelLowUrgent = AndroidNotificationDetails(
    'insulink_alarm_low_urgent',
    'Zucker niedrig — Alarm',
    channelDescription: 'Starker Alarm bei kritisch niedrigem Zuckerwert.',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    playSound: false,
    channelBypassDnd: true,
  );

  static const _channelHighWarning = AndroidNotificationDetails(
    'insulink_alarm_high_warning',
    'Zucker hoch — Warnung',
    channelDescription: 'Warnung bei hohem Zuckerwert.',
    importance: Importance.high,
    priority: Priority.high,
    playSound: false,
    channelBypassDnd: true,
  );

  static const _channelHighUrgent = AndroidNotificationDetails(
    'insulink_alarm_high_urgent',
    'Zucker hoch — Alarm',
    channelDescription: 'Starker Alarm bei kritisch hohem Zuckerwert.',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    playSound: false,
    channelBypassDnd: true,
  );

  /// Play the distinct low/high tone through the ALARM stream so it sounds
  /// regardless of ringer/notification volume, DnD, or screen state. Best-effort:
  /// the notification still shows if audio fails.
  static Future<void> _playSound({required bool high}) async {
    try {
      await _player.play(
        AssetSource(high ? 'sounds/alarm_high.wav' : 'sounds/alarm_low.wav'),
        ctx: AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
    } catch (_) {
      // Audio is best-effort; the visual notification already fired.
    }
  }

  // Plain channel for the non-glucose notifications (connection lost / expiry):
  // default sound, no direction.
  static const _channelWarning = AndroidNotificationDetails(
    'insulink_alarm_warning',
    'Zucker-Warnung',
    channelDescription: 'Leichte Warnung bei grenzwertigem Zuckerwert.',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Must be called once per isolate before [check] (mirrors `RustLib.init()`).
  static Future<void> init(FlutterLocalNotificationsPlugin plugin) async {
    const android = AndroidInitializationSettings('notification');
    await plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
  }

  /// Ask for "Do Not Disturb access" if not yet granted (opens the system
  /// settings page). MUST be granted BEFORE the alarm channels are created, or
  /// `channelBypassDnd` is silently treated as false — so this runs from the UI
  /// (service start + alarm test), before the service isolate posts the first
  /// alarm. Returns whether access is (now) held. Call from the UI isolate only;
  /// the service isolate has no activity to launch the settings screen.
  static Future<bool> ensureDndAccess() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.hasNotificationPolicyAccess() ?? true) return true;
    return await android?.requestNotificationPolicyAccess() ?? false;
  }

  /// Unicode trend arrow for the per-minute trend — mirrors the 5 directional
  /// buckets of the overview readout (`overview_current_value.dart`).
  static String trendArrow(double perMin) {
    if (perMin >= 2) return '↑';
    if (perMin >= 1) return '↗';
    if (perMin > -1) return '→';
    if (perMin > -2) return '↘';
    return '↓';
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

    // Format the value in the user's chosen unit for the notification text,
    // with a trend arrow (same 5 buckets as the overview readout).
    final shown = t.unit == GlucoseUnit.mmol
        ? '${(mgdl / 18.0182).toStringAsFixed(1)} ${t.unit.label}'
        : '$mgdl ${t.unit.label}';
    final value = '$shown ${trendArrow(trendPerMin)}';

    final String title;
    final String body;
    final AndroidNotificationDetails details;
    switch (level) {
      case G7AlarmLevel.lowWarning:
        title = 'Zucker niedrig';
        body = value;
        details = _channelLowWarning;
      case G7AlarmLevel.lowUrgent:
        title = '⚠️ Zucker SEHR niedrig';
        body = value;
        details = _channelLowUrgent;
      case G7AlarmLevel.highWarning:
        title = 'Zucker hoch';
        body = value;
        details = _channelHighWarning;
      case G7AlarmLevel.highUrgent:
        title = '⚠️ Zucker SEHR hoch';
        body = value;
        details = _channelHighUrgent;
      case G7AlarmLevel.none:
        return;
    }
    await _plugin.show(
      id: level.index,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
    );
    await _playSound(
      high:
          level == G7AlarmLevel.highWarning ||
          level == G7AlarmLevel.highUrgent,
    );
  }

  /// Notification id for the sensor-expiry warning (kept clear of the glucose
  /// alarm ids, which use [G7AlarmLevel.index] 0–4).
  static const _expiryId = 100;

  /// Notification id for the "connection lost" warning.
  static const _connectionLostId = 101;

  /// No reading for this long while a sensor is linked ⇒ warn the link is lost.
  static const _connectionLostAfter = Duration(minutes: 15);

  bool _connectionLostShown = false;

  /// Clear any pending "connection lost" warning — call on each fresh reading.
  Future<void> onReading() async {
    if (!_connectionLostShown) return;
    _connectionLostShown = false;
    await _plugin.cancel(id: _connectionLostId);
  }

  /// Warn once when no reading has arrived for [_connectionLostAfter] while a
  /// sensor is linked. Driven by the service watchdog; shown once per outage and
  /// cleared by [onReading]. The toggle + silent flag are read fresh so changes
  /// take effect without restarting the service isolate.
  Future<void> checkConnectionLost({
    required bool sensorLinked,
    required Duration sinceLastReading,
  }) async {
    if (!sensorLinked || sinceLastReading < _connectionLostAfter) return;
    if (_connectionLostShown) return;
    if (!await ProfileConnectionState.load()) return;
    // Suppress while silent WITHOUT marking it shown, so it still fires once
    // silent mode is turned off (if the link is still down).
    if (await ProfileSilentState.load()) return;
    _connectionLostShown = true;
    await _plugin.show(
      id: _connectionLostId,
      title: 'Verbindung verloren',
      body: 'Seit über 15 min kein Wert vom Sensor. Bring dein Handy näher.',
      notificationDetails: const NotificationDetails(android: _channelWarning),
    );
  }

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
