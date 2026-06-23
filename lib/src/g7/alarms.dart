import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../localization/service_strings.dart';
import '../profile/profile_alarm_sound_state.dart';
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
///
/// The alarm TONE is played manually through the ALARM audio stream (see
/// [_playSound]) — NOT via the notification channel. Channel sounds proved
/// unreliable in practice (they obey the notification-volume slider, which can
/// be 0, and the channel's sound/routing is frozen at creation). Playing it
/// ourselves with usage=alarm makes it obey the alarm-volume slider instead and
/// sound through silenced ringer / DnD / screen off, like Dexcom does. So the
/// alarm channels are SILENT (`playSound: false`); they only carry the visual
/// heads-up and the urgent full-screen intent. `channelBypassDnd` still lets the
/// visual alert through DnD.
class G7AlarmManager {
  G7AlarmManager(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final AudioPlayer _player = AudioPlayer(playerId: 'insulink_alarm');
  final ServiceStrings _strings = ServiceStrings();
  G7AlarmLevel _last = G7AlarmLevel.none;

  /// Notification id for the sensor-expiry warning (kept clear of the glucose
  /// alarm ids, which use [G7AlarmLevel.index] 0–4).
  static const _expiryId = 100;

  /// Notification id for the "connection lost" warning.
  static const _connectionLostId = 101;

  /// No reading for this long while a sensor is linked ⇒ warn the link is lost.
  static const _connectionLostAfter = Duration(minutes: 15);

  bool _connectionLostShown = false;

  /// Initialise the notification plugin. Must run once per isolate before
  /// [check] (mirrors `RustLib.init()`).
  Future<void> init() async {
    const android = AndroidInitializationSettings('notification');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
  }

  /// Ask for "Do Not Disturb access" if not yet granted (opens the system
  /// settings page). MUST be granted BEFORE the alarm channels are created, or
  /// `channelBypassDnd` is silently treated as false — so this runs from the UI
  /// (service start + alarm test), before the service isolate posts the first
  /// alarm. Returns whether access is (now) held. Call from the UI isolate only;
  /// the service isolate has no activity to launch the settings screen.
  Future<bool> ensureDndAccess() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.hasNotificationPolicyAccess() ?? true) {
      return true;
    }
    return await android?.requestNotificationPolicyAccess() ?? false;
  }

  /// Unicode trend arrow for the per-minute trend — mirrors the 5 directional
  /// buckets of the overview readout (`overview_current_value.dart`).
  String trendArrow(double perMin) {
    if (perMin >= 2) {
      return '↑';
    }
    if (perMin >= 1) {
      return '↗';
    }
    if (perMin > -1) {
      return '→';
    }
    if (perMin > -2) {
      return '↘';
    }
    return '↓';
  }

  /// Evaluate a new reading and notify on entering a different alarm zone.
  /// Re-evaluating the same zone repeatedly (e.g. every 5 min EGV) does not
  /// re-notify, so the alarm only fires again once the value has recovered and
  /// crossed back in, or escalated/de-escalated to a different zone. The zone is
  /// tracked even while silent, so it doesn't fire on the FIRST reading after
  /// silent mode is switched off if glucose is still in-zone — only on a fresh
  /// crossing. Thresholds, display unit, and the silent flag are read fresh from
  /// storage each call so profile changes take effect without a service restart.
  Future<void> check(int? mgdl, double trendPerMin) async {
    if (mgdl == null) {
      return;
    }
    final thresholds = await ProfileGlucoseState.loadThresholds();
    final level = _levelFor(mgdl, thresholds);
    if (level == _last) {
      return;
    }
    _last = level;
    if (level == G7AlarmLevel.none) {
      return;
    }
    if (await ProfileSilentState.load()) {
      return;
    }
    await _show(level, _formatValue(mgdl, thresholds.unit, trendPerMin));
    await _playSound(high: _isHigh(level));
  }

  /// Clear any pending "connection lost" warning — call on each fresh reading.
  Future<void> onReading() async {
    if (!_connectionLostShown) {
      return;
    }
    _connectionLostShown = false;
    await _plugin.cancel(id: _connectionLostId);
  }

  /// Warn once when no reading has arrived for [_connectionLostAfter] while a
  /// sensor is linked. Driven by the service watchdog; shown once per outage and
  /// cleared by [onReading]. Suppressed while silent WITHOUT marking it shown,
  /// so it still fires once silent mode is turned off (if the link is still
  /// down). The toggle + silent flag are read fresh so changes take effect
  /// without restarting the service isolate.
  Future<void> checkConnectionLost({
    required bool sensorLinked,
    required Duration sinceLastReading,
  }) async {
    if (!sensorLinked || sinceLastReading < _connectionLostAfter) {
      return;
    }
    if (_connectionLostShown) {
      return;
    }
    if (!await ProfileConnectionState().load()) {
      return;
    }
    if (await ProfileSilentState.load()) {
      return;
    }
    _connectionLostShown = true;
    await _plugin.show(
      id: _connectionLostId,
      title: await _strings.get('alarm.connection_lost.title'),
      body: await _strings.get('alarm.connection_lost.body'),
      notificationDetails: NotificationDetails(
        android: await _warningChannel(),
      ),
    );
  }

  /// Fire a one-shot "sensor expires soon" warning once less than 24 h of the
  /// session remains. Persisted per-sensor in [store] so it fires only once per
  /// sensor, even across service/app restarts. Suppressed while silent WITHOUT
  /// marking it notified, so the one-shot warning still fires once silent mode
  /// is turned off (if there's time left).
  Future<void> checkExpiry({
    required G7Store store,
    required String key,
    required int? sessionLengthSec,
    required int secsSinceStart,
  }) async {
    if (key.isEmpty || sessionLengthSec == null) {
      return;
    }
    final remaining = sessionLengthSec - secsSinceStart;
    if (remaining <= 0 || remaining > 86400) {
      return;
    }
    if (await ProfileSilentState.load()) {
      return;
    }
    if (store.expiryNotified(key)) {
      return;
    }
    await store.setExpiryNotified(key);
    final hours = (remaining / 3600).ceil();
    await _plugin.show(
      id: _expiryId,
      title: await _strings.get('alarm.expiry.title'),
      body: await _strings.format('alarm.expiry.body', hours),
      notificationDetails: NotificationDetails(
        android: await _warningChannel(),
      ),
    );
  }

  /// Whether a level is a high (vs low) glucose alarm.
  bool _isHigh(G7AlarmLevel level) =>
      level == G7AlarmLevel.highWarning || level == G7AlarmLevel.highUrgent;

  /// Map a reading to its alarm zone using the user's thresholds.
  G7AlarmLevel _levelFor(
    int mgdl,
    ({GlucoseUnit unit, int urgentLow, int low, int high, int urgentHigh}) t,
  ) {
    if (mgdl <= t.urgentLow) {
      return G7AlarmLevel.lowUrgent;
    }
    if (mgdl >= t.urgentHigh) {
      return G7AlarmLevel.highUrgent;
    }
    if (mgdl <= t.low) {
      return G7AlarmLevel.lowWarning;
    }
    if (mgdl >= t.high) {
      return G7AlarmLevel.highWarning;
    }
    return G7AlarmLevel.none;
  }

  /// The notification body: the value in the user's chosen unit plus a trend
  /// arrow (same 5 buckets as the overview readout).
  String _formatValue(int mgdl, GlucoseUnit unit, double trendPerMin) {
    final shown = unit == GlucoseUnit.mmol
        ? '${(mgdl / 18.0182).toStringAsFixed(1)} ${unit.label}'
        : '$mgdl ${unit.label}';
    return '$shown ${trendArrow(trendPerMin)}';
  }

  /// Post the glucose alarm notification for [level] with [body].
  Future<void> _show(G7AlarmLevel level, String body) async {
    await _plugin.show(
      id: level.index,
      title: await _strings.get(_titleKey(level)),
      body: body,
      notificationDetails: NotificationDetails(
        android: await _alarmChannel(level),
      ),
    );
  }

  /// Localization key for a glucose alarm's title.
  String _titleKey(G7AlarmLevel level) {
    switch (level) {
      case G7AlarmLevel.lowWarning:
        return 'alarm.low.title';
      case G7AlarmLevel.lowUrgent:
        return 'alarm.low_urgent.title';
      case G7AlarmLevel.highWarning:
        return 'alarm.high.title';
      case G7AlarmLevel.highUrgent:
        return 'alarm.high_urgent.title';
      case G7AlarmLevel.none:
        return '';
    }
  }

  /// Build the (silent, DnD-bypassing) channel for a glucose alarm. Urgent
  /// levels add a full-screen intent + the alarm category. Channel ids,
  /// importance and flags are fixed; only the user-facing name/description are
  /// localized (Android freezes those at channel-creation time).
  Future<AndroidNotificationDetails> _alarmChannel(G7AlarmLevel level) async {
    final urgent =
        level == G7AlarmLevel.lowUrgent || level == G7AlarmLevel.highUrgent;
    final slug = switch (level) {
      G7AlarmLevel.lowWarning => 'low_warning',
      G7AlarmLevel.lowUrgent => 'low_urgent',
      G7AlarmLevel.highWarning => 'high_warning',
      G7AlarmLevel.highUrgent => 'high_urgent',
      G7AlarmLevel.none => 'warning',
    };
    return AndroidNotificationDetails(
      'insulink_alarm_$slug',
      await _strings.get('alarm.channel.$slug.name'),
      channelDescription: await _strings.get('alarm.channel.$slug.desc'),
      importance: urgent ? Importance.max : Importance.high,
      priority: urgent ? Priority.max : Priority.high,
      fullScreenIntent: urgent,
      category: urgent ? AndroidNotificationCategory.alarm : null,
      playSound: false,
      channelBypassDnd: true,
    );
  }

  /// Plain channel for the non-glucose warnings (connection lost / expiry):
  /// default sound, no direction.
  Future<AndroidNotificationDetails> _warningChannel() async {
    return AndroidNotificationDetails(
      'insulink_alarm_warning',
      await _strings.get('alarm.channel.warning.name'),
      channelDescription: await _strings.get('alarm.channel.warning.desc'),
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  /// Play the distinct low/high tone through the ALARM stream so it sounds
  /// regardless of ringer/notification volume, DnD, or screen state. Best-effort:
  /// the notification still shows if audio fails or the user disabled the tone.
  Future<void> _playSound({required bool high}) async {
    if (!await ProfileAlarmSoundState().load()) {
      return;
    }
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
      // ponytail: audio is best-effort; the visual notification already fired.
    }
  }
}
