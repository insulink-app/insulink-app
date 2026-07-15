import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../injection/active_insulin.dart';
import '../../localization/service_strings.dart';
import '../../nutrition/meal/meal_store.dart';
import '../../profile/bolus/profile_bolus_state.dart';
import '../../profile/notifications/notification_setting.dart';
import '../../profile/notifications/profile_alarm_sound_state.dart';
import '../../profile/notifications/profile_connection_state.dart';
import '../../profile/glucose/profile_glucose_state.dart';
import '../../profile/prediction/profile_prediction_state.dart';
import '../../profile/silent/profile_silent_state.dart';
import '../../sport/sport_store.dart';
import '../../sport/training/cardio_models.dart';
import '../cgm_store.dart';
import '../glucose_prediction.dart';

/// Notification-action ids for the "training detected" confirm prompt.
const String _trainingConfirmAction = 'training_confirm';
const String _trainingRejectAction = 'training_reject';

/// Records a Confirm/Reject tap on the "training detected" notification. This
/// runs in the bare background isolate `flutter_local_notifications` spawns for
/// action taps (even while the app is foreground) — it has NO
/// `flutter_secure_storage`, so it can't touch [SportStore]'s pending list
/// directly. It appends the decision to a plain file (plugin-free `dart:io`,
/// synchronous so it finishes before the isolate is torn down); the service
/// isolate applies it via [SportStore.applyTrainingDecisions] on its next
/// watchdog tick, and the UI re-reads pending on its next resume.
@pragma('vm:entry-point')
void trainingNotificationAction(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) {
    return;
  }
  // Payload is "id\nwritableFilePath" (see notifyTrainingDetected). The path is
  // resolved in the plugin-capable service isolate because this bare action-tap
  // isolate can't resolve its own writable temp dir (see SportStore).
  final newline = payload.indexOf('\n');
  final id = newline < 0 ? payload : payload.substring(0, newline);
  final filePath = newline < 0 ? null : payload.substring(newline + 1);
  if (id.isEmpty) {
    return;
  }
  const store = SportStore();
  if (response.actionId == _trainingConfirmAction) {
    store.recordTrainingDecision('confirm', id, filePath: filePath);
  } else if (response.actionId == _trainingRejectAction) {
    store.recordTrainingDecision('reject', id, filePath: filePath);
  }
}

/// Glucose alarm severity. Ordered so a transition between two non-`none`
/// levels (e.g. urgent low → warning low) still re-fires the notification.
enum G7AlarmLevel { none, lowWarning, lowUrgent, highWarning, highUrgent }

/// Predictive advisory zone: glucose is currently in range but forecast to
/// cross the low or high threshold within the advisory horizon.
enum AdvisoryLevel { none, low, high }

/// What the advisory expects over its horizon. [low]/[high] are the EXPECTED
/// extremes — the forecast curve's mean points, blended with the trend line.
/// [bandLow] is the same low extreme but taking each point's conformal q10 bound
/// where the model served one.
///
/// The two exist side by side because the low pre-warning and everything after
/// it want different questions answered. Whether to warn at all is "could this
/// go low?", and the mean answers it badly: an L2 point forecast is the
/// conditional mean, so it is correctly shrunk toward the middle and barely ever
/// dips below the low line (the backend measures 1.9% recall of <70 at 60 min,
/// against 47.5% at q10 — see its `BAND_QUANTILES`). So [bandLow] drives the low
/// trigger AND its re-arm: both sides of that hysteresis must read the same
/// signal, or a band trigger that re-arms on the mean nags every reading.
///
/// Sizing the rescue carbs and naming a number in the notification are the other
/// question — "what will most likely happen?" — and there the pessimistic tail
/// would over-treat a low that may never materialise (the very thing
/// [_rescueTargetMarginMgdl] exists to avoid). Those keep reading [low].
///
/// The high side deliberately has no band equivalent, even though the mean misses
/// highs just as badly (4.3% recall of >180, against 50.2% at q90). Two reasons,
/// neither about the dose itself — that is now just the current-value correction
/// (see [_advisoryBody]), so a false high advisory only ever suggests what the
/// calculator would suggest anyway.
///
/// First, noise: a rise past `high` after a meal is normal and expected, so a q90
/// trigger would fire at nearly every meal, and an advisory nobody reads protects
/// nobody. Second, [ProfileBolusState.suggestedBolus] still does not subtract
/// insulin-on-board (`ActiveInsulin` exists, but only feeds the overview readout),
/// so repeated high advisories can still prompt stacked corrections. Revisit the
/// q90 trigger once IOB reaches the calculator.
///
/// Sensitivity is what the low side needs; the high side needs specificity.
typedef AdvisoryForecast = ({double low, double high, double bandLow});

/// Watches live EGV readings and raises local notifications when glucose
/// crosses into a low/high zone. Runs inside the foreground-service isolate
/// (same place [CgmTaskHandler] lives) so alarms fire even with the app closed.
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
  final CgmStore? _store;
  final AudioPlayer _player = AudioPlayer(playerId: 'insulink_alarm');
  final ServiceStrings _strings = ServiceStrings();
  G7AlarmLevel _last = G7AlarmLevel.none;
  bool _lowAdvisoryArmed = true;
  bool _highAdvisoryArmed = true;

  /// Notification id for the sensor-expiry warning (kept clear of the glucose
  /// alarm ids, which use [G7AlarmLevel.index] 0–4).
  static const _expiryId = 100;

  /// Notification id for the "connection lost" warning.
  static const _connectionLostId = 101;

  /// Notification id for the "training detected" confirm prompt.
  static const _trainingDetectedId = 102;

  /// Notification id for the "sensor halfway through its life" reminder.
  static const _halftimeId = 103;

  /// Notification id for the predictive glucose advisory pre-warning.
  static const _advisoryId = 104;

  /// How many minutes ahead the advisory projects the current value + trend.
  /// Kept deliberately short so the pre-warning fires only when the low/high is
  /// genuinely imminent, not on every distant projection.
  static const _advisoryHorizonMin = 15;

  /// Grams of fast carbs per glucose tablet ("Plättchen"), for the hypo
  /// countermeasure's tablet-count conversion.
  static const _gramsPerTablet = 6;

  /// How far above the low line / below the high line the rescue countermeasure
  /// aims to bring glucose back to. A modest safe buffer — NOT the middle of the
  /// target range — so the suggested carbs stay small (over-treating a predicted
  /// low, when it may not even fully materialise, is worse than a small top-up).
  static const _rescueTargetMarginMgdl = 20;

  /// How far glucose must recover past the alarm line before an advisory re-arms
  /// (rise above `low + margin` / fall below `high - margin`). Until then a
  /// forecast wobbling around the threshold cannot re-fire the same episode's
  /// pre-warning — it shows once, then only again after a real recovery.
  static const _advisoryRearmMarginMgdl = 30;

  /// A cached backend prediction older than this is ignored — only the UI
  /// isolate refreshes it, so with the app closed it goes stale and the advisory
  /// falls back to the pure trend projection.
  static const _predictionMaxAgeMin = 10;

  /// A short triple-buzz, distinct from the glucose ([_vibrationPattern]) and
  /// training ([_trainingVibrationPattern]) patterns, so the advisory feels its
  /// own.
  static const _advisoryVibrationPattern = [0, 100, 60, 100, 60, 100];

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

  /// Raise a PRE-warning before glucose actually reaches a low/high zone and
  /// suggest a countermeasure: insulin units for a predicted high, grams of fast
  /// carbs (plus a tablet count) for a predicted low. The forecast is driven
  /// primarily by the current value + trend projected [_advisoryHorizonMin] min
  /// ahead; a fresh backend prediction curve refines it when available. Fires
  /// ONCE per episode: after a low/high pre-warning it is disarmed and only
  /// re-arms once glucose has genuinely recovered ([_rearmAdvisories]) — a
  /// forecast wobbling around the threshold does not nag repeatedly. Has its own
  /// toggle; suppressed while glucose is already out of range (the real alarm
  /// owns that) and while silent. Settings are read fresh so changes apply
  /// without a service restart.
  Future<void> checkAdvisory(int? mgdl, double trendPerMin) async {
    if (mgdl == null) {
      return;
    }
    if (!await NotificationSetting.advisory.load()) {
      return;
    }
    final glucose = await ProfileGlucoseState.load();
    final forecast = await _forecast(mgdl, trendPerMin);
    _rearmAdvisories(forecast, glucose);
    final level = advisoryLevelFor(mgdl, (
      low: forecast.bandLow,
      high: forecast.high,
    ), (low: glucose.low, high: glucose.high));
    if (level == AdvisoryLevel.none) {
      return;
    }
    if (level == AdvisoryLevel.low && !_lowAdvisoryArmed) {
      return;
    }
    if (level == AdvisoryLevel.high && !_highAdvisoryArmed) {
      return;
    }
    if (await ProfileSilentState.load()) {
      return;
    }
    await _showAdvisory(
      level,
      await _advisoryBody(level, mgdl, trendPerMin, forecast, glucose),
    );
    await _playAdvisorySound(level);
    if (level == AdvisoryLevel.low) {
      _lowAdvisoryArmed = false;
    } else {
      _highAdvisoryArmed = false;
    }
  }

  /// Re-arm an advisory once the FORECAST has recovered clearly past the alarm
  /// line (projected low back above `low + margin`, or projected high back below
  /// `high - margin`). Keyed on the forecast, not the current value: the advisory
  /// fires while glucose is still in range, so the current value is usually
  /// already past the re-arm line at the moment it fires — re-arming on it would
  /// re-fire the same episode on the very next reading. Waiting for the forecast
  /// itself to recover is the real "episode over" signal, so a projection that
  /// keeps threatening (or wobbles around the threshold) can't nag repeatedly.
  ///
  /// Each side re-arms on the SAME quantity that triggers it — the low on
  /// [AdvisoryForecast.bandLow], the high on [AdvisoryForecast.high]. Mixing them
  /// would break the hysteresis: a low that triggers on the band but re-arms on
  /// the (higher) mean would re-arm while the band still threatens, and fire again
  /// on the very next reading.
  void _rearmAdvisories(
    AdvisoryForecast forecast,
    ProfileGlucoseState glucose,
  ) {
    if (forecast.bandLow >= glucose.low + _advisoryRearmMarginMgdl) {
      _lowAdvisoryArmed = true;
    }
    if (forecast.high <= glucose.high - _advisoryRearmMarginMgdl) {
      _highAdvisoryArmed = true;
    }
  }

  /// Decide the advisory zone. Pure and static so it can be unit-tested without
  /// the notification plugin. A value already at/over the warning thresholds is
  /// left to the real glucose alarm — the advisory only pre-warns while in range.
  @visibleForTesting
  static AdvisoryLevel advisoryLevelFor(
    int mgdl,
    ({double low, double high}) forecast,
    ({int low, int high}) thresholds,
  ) {
    if (mgdl <= thresholds.low || mgdl >= thresholds.high) {
      return AdvisoryLevel.none;
    }
    if (forecast.low <= thresholds.low) {
      return AdvisoryLevel.low;
    }
    if (forecast.high >= thresholds.high) {
      return AdvisoryLevel.high;
    }
    return AdvisoryLevel.none;
  }

  /// Forecast the glucose extremes [_advisoryHorizonMin] min ahead. The trend
  /// line is the always-available base; a fresh cached prediction curve nudges
  /// the extremes toward whichever direction warns earlier.
  ///
  /// [AdvisoryForecast.low]/[AdvisoryForecast.high] are the EXPECTED extremes
  /// (the curve's mean points); [AdvisoryForecast.bandLow] additionally lets each
  /// point contribute its q10 band bound instead of its mean, and is what the low
  /// pre-warning triggers on — see the typedef for why only the low side.
  Future<AdvisoryForecast> _forecast(int mgdl, double trendPerMin) async {
    final linear = mgdl + trendPerMin * _advisoryHorizonMin;
    var low = linear;
    var high = linear;
    var bandLow = linear;
    for (final point
        in await _freshPredictionCurve() ?? const <PredictionPoint>[]) {
      if (point.offsetMin <= 0 || point.offsetMin > _advisoryHorizonMin) {
        continue;
      }
      low = math.min(low, point.mgdl.toDouble());
      high = math.max(high, point.mgdl.toDouble());
      bandLow = math.min(bandLow, (point.lo ?? point.mgdl).toDouble());
    }
    return (low: low, high: high, bandLow: bandLow);
  }

  /// The cached prediction points, but only when predictions are enabled and the
  /// forecast is still recent. Returns null otherwise so the advisory falls back
  /// to the pure trend projection.
  /// ponytail: only the UI isolate refreshes [PredictionCache], so with the app
  /// closed this goes stale within minutes and is correctly ignored here.
  Future<List<PredictionPoint>?> _freshPredictionCurve() async {
    if (!(await ProfilePredictionState.load()).enabled) {
      return null;
    }
    final cached = await PredictionCache().load();
    if (cached == null) {
      return null;
    }
    final ageMin = DateTime.now().difference(cached.base).inMinutes;
    if (ageMin < 0 || ageMin > _predictionMaxAgeMin) {
      return null;
    }
    return cached.points;
  }

  /// The advisory body: the localized suggestion plus a concrete countermeasure
  /// derived from the user's bolus factors and the midpoint of their target
  /// range. Low → grams of fast carbs (with a tablet count); high → insulin units.
  ///
  /// The two sides answer different questions on purpose.
  ///
  /// Carbs are a RESCUE, so they size off where glucose is heading
  /// ([AdvisoryForecast.low], the expected dip — never the band, whose tail would
  /// over-treat a low that may not materialise).
  ///
  /// Insulin is a CORRECTION, so it sizes off [mgdl] — where glucose is NOW — and
  /// is therefore exactly the dose [InjectionPage] would suggest for the same
  /// reading with no carbs entered. Both go through [ProfileBolusState.suggestedBolus]
  /// against [ProfileGlucoseState.targetMid], so the two screens cannot disagree.
  /// Dosing off the predicted PEAK (what this used to do) always exceeded the
  /// calculator, because the advisory only fires while the peak is still ahead of
  /// the current value.
  Future<String> _advisoryBody(
    AdvisoryLevel level,
    int mgdl,
    double trendPerMin,
    AdvisoryForecast forecast,
    ProfileGlucoseState glucose,
  ) async {
    final line = await _forecastLine(
      level,
      mgdl,
      trendPerMin,
      forecast,
      glucose.unit,
    );
    final bolus = await ProfileBolusState.load();
    if (level == AdvisoryLevel.low) {
      final grams = bolus.suggestedRescueCarbs(
        glucoseMgdl: forecast.low.round(),
        targetMgdl: glucose.low + _rescueTargetMarginMgdl,
      );
      final tablets = (grams / _gramsPerTablet).ceil();
      final suggestion = await _strings.formatAll('alarm.advisory.low_body', [
        grams.ceil(),
        tablets,
      ]);
      return '$line\n$suggestion';
    }
    final units = bolus.suggestedBolus(
      carbs: 0,
      glucoseMgdl: mgdl,
      targetMgdl: glucose.targetMid,
      iobUnits: await _activeInsulin(bolus),
    );
    final suggestion = await _strings.format(
      'alarm.advisory.high_body',
      units.toStringAsFixed(1),
    );
    return '$line\n$suggestion';
  }

  /// Units still active from earlier boluses, straight from the meal log's store.
  ///
  /// This isolate has no providers, so it cannot reach `MealState` the way the
  /// injection sheet does — [MealStore] is the shared bottom layer both sit on,
  /// and reading it fresh per advisory is what keeps the two suggestions equal.
  Future<double> _activeInsulin(ProfileBolusState bolus) async {
    final meals = await const MealStore().loadMeals();
    return ActiveInsulin(bolus.insulinDuration).units(meals);
  }

  /// The "now → forecast" status line prepended to the advisory body: the
  /// current value with its trend arrow, and the projected extreme the horizon
  /// ahead (the low for a predicted low, the high for a predicted high).
  Future<String> _forecastLine(
    AdvisoryLevel level,
    int mgdl,
    double trendPerMin,
    AdvisoryForecast forecast,
    GlucoseUnit unit,
  ) {
    final predicted = level == AdvisoryLevel.low ? forecast.low : forecast.high;
    return _strings.formatAll('alarm.advisory.forecast', [
      _formatValue(mgdl, unit, trendPerMin),
      _advisoryHorizonMin,
      _formatMgdl(predicted.round(), unit),
    ]);
  }

  /// Post the advisory pre-warning notification.
  Future<void> _showAdvisory(AdvisoryLevel level, String body) async {
    final titleKey = level == AdvisoryLevel.low
        ? 'alarm.advisory.low_title'
        : 'alarm.advisory.high_title';
    await _plugin.show(
      id: _advisoryId,
      title: await _strings.get(titleKey),
      body: body,
      notificationDetails: NotificationDetails(
        android: await _advisoryChannel(),
      ),
    );
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
    required CgmStore store,
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
    required CgmStore store,
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

  /// Stable event-log slug for a glucose alarm level (the analysis events page
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
    return '${_formatMgdl(mgdl, unit)} ${trendArrow(trendPerMin)}';
  }

  /// A glucose value in the user's chosen unit, without a trend arrow.
  String _formatMgdl(int mgdl, GlucoseUnit unit) {
    return unit == GlucoseUnit.mmol
        ? '${(mgdl / 18.0182).toStringAsFixed(1)} ${unit.label}'
        : '$mgdl ${unit.label}';
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

  /// Silent, DnD-bypassing channel for the predictive advisory pre-warning. A
  /// predicted low is safety-relevant, so it bypasses DnD like the glucose
  /// alarms, but it is a heads-up (not a full-screen in-progress emergency).
  Future<AndroidNotificationDetails> _advisoryChannel() async {
    return AndroidNotificationDetails(
      'insulink_alarm_advisory',
      await _strings.get('alarm.channel.advisory.name'),
      channelDescription: await _strings.get('alarm.channel.advisory.desc'),
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      channelBypassDnd: true,
      vibrationPattern: Int64List.fromList(_advisoryVibrationPattern),
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
        .replaceFirst(
          '#',
          await _strings.get('sport.trainings.${training.type.name}'),
        )
        .replaceFirst('#', '${training.duration.inMinutes}');
    await _plugin.show(
      id: _trainingDetectedId,
      title: await _strings.get('sport.detect_notification.title'),
      body: body,
      notificationDetails: NotificationDetails(
        android: await _trainingChannel(),
      ),
      // Carry the writable hand-off path so the action-tap isolate writes where
      // the drain reads (see trainingNotificationAction / SportStore).
      payload: '${training.id}\n${const SportStore().decisionFilePath}',
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

  /// Play the distinct low/high tone through the ALARM stream.
  Future<void> _playSound({required bool high}) =>
      _playAsset(high ? 'sounds/alarm_high.wav' : 'sounds/alarm_low.wav');

  /// Play the pre-warning tone for an imminent low/high, one distinct sound per
  /// direction so the two are audibly distinguishable.
  Future<void> _playAdvisorySound(AdvisoryLevel level) => _playAsset(
    level == AdvisoryLevel.low
        ? 'sounds/alarm_low_soon.wav'
        : 'sounds/alarm_high_soon.wav',
  );

  /// Play [asset] through the ALARM stream so it sounds regardless of ringer/
  /// notification volume, DnD, or screen state. Best-effort: the notification
  /// still shows if audio fails or the user disabled the tone.
  Future<void> _playAsset(String asset) async {
    if (!await ProfileAlarmSoundState().load()) {
      return;
    }
    try {
      await _player.play(
        AssetSource(asset),
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
