import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../localization/service_strings.dart';
import '../../profile/notifications/notification_setting.dart';
import '../../profile/notifications/profile_alarm_sound_state.dart';
import '../../profile/notifications/profile_connection_state.dart';
import '../../profile/glucose/profile_glucose_state.dart';
import '../../profile/silent/profile_silent_state.dart';
import '../../sport/sport_store.dart';
import '../../sport/training/cardio_models.dart';
import '../store.dart';

/// Notification-action ids for the "training detected" confirm prompt.
const String _trainingConfirmAction = 'training_confirm';
const String _trainingRejectAction = 'training_reject';

/// Applies a Confirm/Reject tap on the "training detected" notification straight
/// to the store — used for the foreground tap AND as the `vm:entry-point`
/// background handler (app closed). The UI re-reads pending on its next resume.
/// `ponytail:` fire-and-forget; a secure-storage read/write is quick and the
/// plugin keeps the background isolate alive long enough for it.
@pragma('vm:entry-point')
void trainingNotificationAction(NotificationResponse response) {
  final id = response.payload;
  if (id == null || id.isEmpty) {
    return;
  }
  const store = SportStore();
  if (response.actionId == _trainingConfirmAction) {
    store.confirmPendingTraining(id);
  } else if (response.actionId == _trainingRejectAction) {
    store.rejectPendingTraining(id);
  }
}

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
  G7AlarmManager(this._plugin, [this._store]);

  final FlutterLocalNotificationsPlugin _plugin;
  // The event log sink. Null for the UI-isolate managers that only run
  // ensureDndAccess()/fireTest() (which log nothing); the service isolate passes
  // its store so glucose/signal events are recorded.
  final G7Store? _store;
  final AudioPlayer _player = AudioPlayer(playerId: 'insulink_alarm');
  final ServiceStrings _strings = ServiceStrings();
  G7AlarmLevel _last = G7AlarmLevel.none;

  /// Notification id for the sensor-expiry warning (kept clear of the glucose
  /// alarm ids, which use [G7AlarmLevel.index] 0–4).
  static const _expiryId = 100;

  /// Notification id for the "connection lost" warning.
  static const _connectionLostId = 101;

  /// Notification id for the "training detected" confirm prompt.
  static const _trainingDetectedId = 102;

  /// Notification id for the "sensor halfway through its life" reminder.
  static const _halftimeId = 103;

  /// How long after the true halfway crossing the reminder stays eligible. The
  /// persisted flag is the normal one-shot guard, but it doesn't survive an app
  /// reinstall / cleared storage; without this window a fresh isolate would re-fire
  /// the reminder for the ENTIRE second half (days 5–10 of a G7) — the user got it
  /// "again and again" on day 7/8, still claiming halftime. Bounding eligibility to
  /// a few hours makes a fire past the actual midpoint impossible.
  static const _halftimeWindowSec = 6 * 3600;

  /// A short double-buzz, deliberately DISTINCT from the glucose alarm pattern so
  /// a detected training doesn't feel like an alarm.
  static const _trainingVibrationPattern = [0, 60, 40, 60];

  /// No reading for this long while a sensor is linked ⇒ warn the link is lost.
  static const _connectionLostAfter = Duration(minutes: 15);

  //The vibration pattern for the notifications
  static const _vibrationPattern = [0, 150, 80, 150, 80, 300];

  bool _connectionLostShown = false;
  bool _signalLossLogged = false;

  /// Initialise the notification plugin. Must run once per isolate before
  /// [check] (mirrors `RustLib.init()`).
  Future<void> init() async {
    const android = AndroidInitializationSettings('notification');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: trainingNotificationAction,
      onDidReceiveBackgroundNotificationResponse: trainingNotificationAction,
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
    final level = levelFor(mgdl, thresholds);
    if (level == _last) {
      return;
    }
    final leftTargetRange =
        _last == G7AlarmLevel.none && level != G7AlarmLevel.none;
    _last = level;
    if (level == G7AlarmLevel.none) {
      return;
    }
    // Only log ONE event per excursion: on leaving the target range. Escalating
    // within the same out-of-range spell (low warning → urgent low, or back)
    // still re-fires the notification below, but does not open a new event — a
    // fresh event needs glucose to have recovered into range in between.
    if (leftTargetRange) {
      await _store?.addEvent(eventTypeFor(level), value: mgdl);
    }
    if (await ProfileSilentState.load()) {
      return;
    }
    await _show(level, _formatValue(mgdl, thresholds.unit, trendPerMin));
    await _playSound(high: _isHigh(level));
  }

  /// Fire a test alarm on demand from the settings UI: the low/high glucose
  /// notification plus its tone, with a sample value. Bypasses the edge-trigger
  /// and the silent gating so the user can preview exactly what an alarm looks
  /// and sounds like; the tone still respects the alarm-sound toggle.
  Future<void> fireTest({required bool high}) async {
    final unit = (await ProfileGlucoseState.loadThresholds()).unit;
    final level = high ? G7AlarmLevel.highWarning : G7AlarmLevel.lowWarning;
    final sampleMgdl = high ? 260 : 60;
    final trendPerMin = high ? 1.5 : -1.5;
    await _show(level, _formatValue(sampleMgdl, unit, trendPerMin));
    await _playSound(high: high);
  }

  /// Clear any pending "connection lost" warning — call on each fresh reading.
  Future<void> onReading() async {
    _signalLossLogged = false;
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
    if (!_signalLossLogged) {
      _signalLossLogged = true;
      await _store?.addEvent('signal_loss');
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
    if (!await NotificationSetting.expiry.load()) {
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

  /// Fire a one-shot reminder in a short window right after the sensor passes the
  /// halfway point of its session (≈ day 5 of a 10-day G7). Persisted per-sensor
  /// in [store] so it fires only once per sensor; the window ([_halftimeWindowSec])
  /// caps eligibility so it can't re-fire deep into the second half if that flag is
  /// ever lost. Same silent/toggle gating as [checkExpiry].
  Future<void> checkHalftime({
    required G7Store store,
    required String key,
    required int? sessionLengthSec,
    required int secsSinceStart,
  }) async {
    if (key.isEmpty || sessionLengthSec == null) {
      return;
    }
    final pastHalf = secsSinceStart - sessionLengthSec ~/ 2;
    if (pastHalf < 0 || pastHalf > _halftimeWindowSec) {
      return;
    }
    if (await ProfileSilentState.load()) {
      return;
    }
    if (!await NotificationSetting.halftime.load()) {
      return;
    }
    if (store.halftimeNotified(key)) {
      return;
    }
    await store.setHalftimeNotified(key);
    await _plugin.show(
      id: _halftimeId,
      title: await _strings.get('alarm.halftime.title'),
      body: await _strings.get('alarm.halftime.body'),
      notificationDetails: NotificationDetails(
        android: await _warningChannel(),
      ),
    );
  }

  /// Stable event-log slug for a glucose alarm level (the statistics events page
  /// maps it to a localized label + icon).
  @visibleForTesting
  static String eventTypeFor(G7AlarmLevel level) {
    switch (level) {
      case G7AlarmLevel.lowWarning:
        return 'glucose_low';
      case G7AlarmLevel.lowUrgent:
        return 'glucose_low_urgent';
      case G7AlarmLevel.highWarning:
        return 'glucose_high';
      case G7AlarmLevel.highUrgent:
        return 'glucose_high_urgent';
      case G7AlarmLevel.none:
        return '';
    }
  }

  /// Whether a level is a high (vs low) glucose alarm.
  bool _isHigh(G7AlarmLevel level) =>
      level == G7AlarmLevel.highWarning || level == G7AlarmLevel.highUrgent;

  /// Map a reading to its alarm zone using the user's thresholds. Pure and
  /// static so it can be unit-tested without the notification plugin.
  @visibleForTesting
  static G7AlarmLevel levelFor(
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
      vibrationPattern: Int64List.fromList(_vibrationPattern),
      enableVibration: true,
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
      vibrationPattern: Int64List.fromList(_vibrationPattern),
      enableVibration: true,
    );
  }

  /// Prompt the user to confirm an auto-detected training: Confirm/Reject
  /// actions, a distinct vibration and no alarm tone. The payload carries the
  /// pending training id so [trainingNotificationAction] can resolve it.
  Future<void> notifyTrainingDetected(CardioTraining training) async {
    if (!await NotificationSetting.training.load()) {
      return;
    }
    final template = await _strings.get('sport.detect_notification.body');
    final body = template
        .replaceFirst('#', await _strings.get('sport.trainings.${training.type.name}'))
        .replaceFirst('#', '${training.duration.inMinutes}');
    await _plugin.show(
      id: _trainingDetectedId,
      title: await _strings.get('sport.detect_notification.title'),
      body: body,
      notificationDetails: NotificationDetails(android: await _trainingChannel()),
      payload: training.id,
    );
  }

  Future<AndroidNotificationDetails> _trainingChannel() async {
    return AndroidNotificationDetails(
      'insulink_training_detected',
      await _strings.get('alarm.channel.training_detected.name'),
      channelDescription: await _strings.get(
        'alarm.channel.training_detected.desc',
      ),
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      vibrationPattern: Int64List.fromList(_trainingVibrationPattern),
      enableVibration: true,
      actions: [
        AndroidNotificationAction(
          _trainingConfirmAction,
          await _strings.get('sport.detect_notification.confirm'),
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _trainingRejectAction,
          await _strings.get('sport.detect_notification.reject'),
          cancelNotification: true,
        ),
      ],
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
