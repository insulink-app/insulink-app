import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/localization/service_strings.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';
import 'package:insulink/src/profile/notifications/notification_threshold.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_alarm.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/pump/service/pod_alarm_channels.dart';

/// Pod warnings raised from the service isolate, so they reach the user with the
/// app backgrounded or closed.
///
/// **The pod's own beeper is the primary alarm.** It sounds on occlusion, an empty
/// reservoir and expiry whether or not this app is running, and it does not depend
/// on a radio link. These notifications are the supplement that also reaches a
/// phone in another room, and that can say WHY — the pod can only beep.
///
/// Two of the checks need no contact with the pod at all
/// ([checkExpiry], [checkReachable]), which is deliberate: they are the ones that
/// still work when the link is down, and a link that is down is itself one of the
/// things worth warning about.
///
/// Shares the notification plugin with [G7AlarmManager] rather than making its
/// own — one plugin per isolate, initialised once by whoever owns the isolate.
class PodAlarmManager {
  PodAlarmManager(this._plugin);

  final PodAlarmChannels _channels = PodAlarmChannels();

  final FlutterLocalNotificationsPlugin _plugin;
  final ServiceStrings _strings = ServiceStrings();

  /// The last alarm kind reported, so a standing alarm notifies once rather than
  /// on every poll. Per-isolate, which is enough: a restarted service re-reads the
  /// pod and re-warns, which is the safe direction.
  PodAlarmKind _lastAlarmKind = PodAlarmKind.none;

  /// Whether the pod was last seen delivering, so a stop is reported on the edge.
  bool _wasDelivering = true;

  /// Notification ids, kept clear of the CGM manager's 0–104.
  static const _expiryId = 110;
  static const _expiredId = 111;
  static const _reservoirId = 112;
  static const _alarmId = 113;
  static const _unreachableId = 114;
  static const _stoppedId = 115;
  static const _loopStoppedId = 116;

  /// One-shot flag names, stored per pod.
  static const _expirySlug = 'expiry';
  static const _expiredSlug = 'expired';
  static const _reservoirSlug = 'reservoir';

  /// How long without a status read before the link counts as lost. Three missed
  /// polls, so one failed attempt does not cry wolf.
  static const Duration unreachableAfter = Duration(minutes: 45);

  /// How often a link that STAYS down is said again.
  ///
  /// The reachability check runs on every watchdog tick, which is every thirty
  /// seconds, and it used to post its notification on each of them. Android
  /// replaces a notification of the same id, so it looked like one notice until
  /// the user swiped it away and it came back half a minute later, alerting
  /// again, for as long as the pod was out of range. That is the reported
  /// spamming. The condition is worth repeating, because a pod nobody can reach
  /// may still be delivering, but at a human interval and not at the watchdog's.
  static const Duration repeatUnreachableEvery = Duration(hours: 1);

  /// When the unreachable notice was last raised, or null while the link is up.
  /// Per-isolate, like [_lastAlarmKind]: a restarted service warns again, which
  /// is the safe direction.
  DateTime? _unreachableNoticedAt;

  /// Warns once the pod has less life left than the user's configured threshold,
  /// and once more when it has actually run out.
  ///
  /// Needs no contact with the pod — the activation time and the pod's reported
  /// lifetime are both local, so this is the one warning that always works.
  Future<void> checkExpiry(PodStore store) async {
    final expires = store.expiresAt;
    if (expires == null || store.podKey == null) {
      return;
    }
    final remaining = expires.difference(DateTime.now());
    if (remaining.isNegative) {
      await _fireOnce(
        store: store,
        slug: _expiredSlug,
        id: _expiredId,
        titleKey: 'alarm.pod.expired.title',
        bodyKey: 'alarm.pod.expired.body',
        setting: NotificationSetting.podExpiry,
      );
      return;
    }
    final thresholdHours = await NotificationThreshold.podExpiry.load();
    if (remaining.inMinutes > thresholdHours * 60) {
      return;
    }
    await _fireOnce(
      store: store,
      slug: _expirySlug,
      id: _expiryId,
      titleKey: 'alarm.pod.expiry.title',
      bodyKey: 'alarm.pod.expiry.body',
      bodyArgument: '${(remaining.inMinutes / 60).ceil()}',
      setting: NotificationSetting.podExpiry,
    );
  }

  /// Warns once the reservoir drops below the user's configured units.
  ///
  /// Skipped while the pod reports more than it can measure — a warning derived
  /// from a sentinel would be a number the pod never gave.
  Future<void> checkReservoir(PodStore store, PodStatusResponse status) async {
    final units = status.reservoirUnits;
    if (units == null) {
      return;
    }
    final threshold = await NotificationThreshold.podInsulin.load();
    if (units > threshold) {
      return;
    }
    await _fireOnce(
      store: store,
      slug: _reservoirSlug,
      id: _reservoirId,
      titleKey: 'alarm.pod.reservoir.title',
      bodyKey: 'alarm.pod.reservoir.body',
      bodyArgument: units.toStringAsFixed(2),
      setting: NotificationSetting.podInsulin,
    );
  }

  /// Reports a pod that has alarmed, naming what kind of problem it is.
  ///
  /// Not gated behind a preference and not one-shot-per-pod: an alarming pod has
  /// STOPPED delivering insulin, which is not something a user can opt out of
  /// being told. Edge-triggered on the kind so a standing alarm notifies once,
  /// and re-armed when the pod reports itself clear again.
  Future<void> checkAlarm(PodAlarm alarm) async {
    if (alarm.kind == _lastAlarmKind) {
      return;
    }
    _lastAlarmKind = alarm.kind;
    if (!alarm.isAlarming) {
      await _plugin.cancel(id: _alarmId);
      return;
    }
    await _plugin.show(
      id: _alarmId,
      title: await _strings.get('alarm.pod.alarm.title'),
      body: await _strings.get(_alarmBodyKey(alarm.kind)),
      notificationDetails: NotificationDetails(
        android: await _channels.urgent(),
      ),
    );
  }

  /// Reports delivery having stopped without us asking for it.
  ///
  /// [PodStore.suspendedByUs] is what keeps a deliberate suspend quiet, so this
  /// only fires for a pod that stopped on its own — the pump hazard that is
  /// otherwise silent, because a pod that is not delivering makes no sound unless
  /// it also alarmed.
  Future<void> checkDelivering(PodStore store, PodStatusResponse status) async {
    final delivering = !status.delivery.isSuspended;
    if (delivering) {
      _wasDelivering = true;
      // The pod delivering again is the authoritative "no longer suspended", so
      // the flag is cleared here rather than by whoever resumed it — a resume can
      // come from the activation, from a retry, or from the pod itself.
      if (store.suspendedByUs) {
        await store.setSuspendedByUs(false);
      }
      await _plugin.cancel(id: _stoppedId);
      return;
    }
    if (!_wasDelivering || store.suspendedByUs) {
      _wasDelivering = false;
      return;
    }
    _wasDelivering = false;
    if (status.lifecycle == PodLifecycleStatus.deactivated) {
      return;
    }
    await _plugin.show(
      id: _stoppedId,
      title: await _strings.get('alarm.pod.stopped.title'),
      body: await _strings.get('alarm.pod.stopped.body'),
      notificationDetails: NotificationDetails(
        android: await _channels.urgent(),
      ),
    );
  }

  /// Warns when the pod has not been reachable for [unreachableAfter], and clears
  /// the warning once it answers again.
  ///
  /// Local, like [checkExpiry]: it is measured from the last successful read, so
  /// it is exactly the case where nothing else can be read.
  ///
  /// Said once per episode and then at most every [repeatUnreachableEvery],
  /// NOT on every tick that finds the link still down.
  Future<void> checkReachable(PodStore store) async {
    final lastSeen = store.lastSeenAt;
    if (lastSeen == null) {
      return;
    }
    final now = DateTime.now();
    final silence = now.difference(lastSeen);
    if (silence < unreachableAfter) {
      _unreachableNoticedAt = null;
      await _plugin.cancel(id: _unreachableId);
      return;
    }
    if ((await ProfileSilentState.load()).mutesNotifications) {
      return;
    }
    final saidAt = _unreachableNoticedAt;
    if (saidAt != null && now.difference(saidAt) < repeatUnreachableEvery) {
      return;
    }
    _unreachableNoticedAt = now;
    await _plugin.show(
      id: _unreachableId,
      title: await _strings.get('alarm.pod.unreachable.title'),
      body: await _strings.format(
        'alarm.pod.unreachable.body',
        silence.inMinutes,
      ),
      notificationDetails: NotificationDetails(
        android: await _channels.warning(),
      ),
    );
  }

  /// Says that the automation switched itself back to the basal schedule.
  ///
  /// An automated system that stops without saying so is worse than one that was
  /// never started: the user goes on believing their delivery is being managed.
  /// Called only when the loop stopped ITSELF; switching it off by hand needs no
  /// notification, because the person who did it is holding the phone.
  ///
  /// The warning channel rather than the urgent one, and it respects silent mode.
  /// Nothing dangerous has happened: the pod has gone back to the schedule the
  /// user programmed, which is exactly where it belongs when nothing is deciding
  /// for it.
  ///
  /// The body reuses the strings the pump page shows for the same cause, so the
  /// notification and the page cannot come to say different things.
  Future<void> loopStopped(PodLoopStop cause) async {
    if ((await ProfileSilentState.load()).mutesNotifications) {
      return;
    }
    await _plugin.show(
      id: _loopStoppedId,
      title: await _strings.get('alarm.pod.loop_stopped.title'),
      body: await _strings.get('pump.loop.stopped.${cause.localeKey}'),
      notificationDetails: NotificationDetails(
        android: await _channels.warning(),
      ),
    );
  }

  /// Fires a warning at most once per pod.
  ///
  /// Suppressed while silent WITHOUT marking it notified, so the one-shot still
  /// fires once silent mode is turned off — the same rule the sensor warnings use.
  Future<void> _fireOnce({
    required PodStore store,
    required String slug,
    required int id,
    required String titleKey,
    required String bodyKey,
    required NotificationSetting setting,
    String? bodyArgument,
  }) async {
    if (store.alarmNotified(slug)) {
      return;
    }
    if ((await ProfileSilentState.load()).mutesNotifications) {
      return;
    }
    if (!await setting.load()) {
      return;
    }
    await store.setAlarmNotified(slug);
    await _plugin.show(
      id: id,
      title: await _strings.get(titleKey),
      body: bodyArgument == null
          ? await _strings.get(bodyKey)
          : await _strings.format(bodyKey, bodyArgument),
      notificationDetails: NotificationDetails(
        android: await _channels.warning(),
      ),
    );
  }

  String _alarmBodyKey(PodAlarmKind kind) => switch (kind) {
    PodAlarmKind.occlusion => 'alarm.pod.alarm.occlusion',
    PodAlarmKind.emptyReservoir => 'alarm.pod.alarm.empty',
    PodAlarmKind.expired => 'alarm.pod.alarm.expired',
    PodAlarmKind.infusionError => 'alarm.pod.alarm.infusion',
    PodAlarmKind.escalatedAlert => 'alarm.pod.alarm.alert',
    PodAlarmKind.communication => 'alarm.pod.alarm.communication',
    _ => 'alarm.pod.alarm.fault',
  };
}
