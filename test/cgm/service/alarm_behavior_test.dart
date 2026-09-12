import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/cgm/service/advisory_action.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_store.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/profile/notifications/profile_alarm_tone_state.dart';

import '../../support/secure_storage_mock.dart';

/// Stubs the audioplayers method channels so the `AudioPlayer` the alarm manager
/// constructs doesn't throw `MissingPluginException` (the tone itself is
/// best-effort and irrelevant to the alarm-decision logic under test).
void silenceAudioPlayers() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
}

/// Mocks the flutter_local_notifications platform channel, recording every
/// `show`/`cancel` so the alarm logic can be exercised without a device. Audio
/// is fired through audioplayers, which has no test platform — every alarm path
/// already wraps `play` in a best-effort try/catch, so it no-ops here.
/// What the mock recorded: the ids shown and cancelled, plus per id the
/// `timeoutAfter` Android was given and how many action buttons it carried.
typedef RecordedNotifications = ({
  List<int> shown,
  List<int> cancelled,
  Map<int, int?> timeouts,
  Map<int, int> actions,
  Map<int, String?> bodies,
});

RecordedNotifications installNotificationMock() {
  final shown = <int>[];
  final cancelled = <int>[];
  final timeouts = <int, int?>{};
  final actions = <int, int>{};
  final bodies = <int, String?>{};
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        if (call.method == 'show') {
          final id = args['id'] as int;
          shown.add(id);
          final android = (args['platformSpecifics'] as Map?);
          timeouts[id] = android?['timeoutAfter'] as int?;
          actions[id] = (android?['actions'] as List?)?.length ?? 0;
          bodies[id] = args['body'] as String?;
        } else if (call.method == 'cancel') {
          cancelled.add(args['id'] as int);
        } else if (call.method == 'initialize') {
          return true;
        }
        return null;
      });
  return (
    shown: shown,
    cancelled: cancelled,
    timeouts: timeouts,
    actions: actions,
    bodies: bodies,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;
  late RecordedNotifications notifications;
  late G7AlarmManager alarms;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    storage = installSecureStorageMock();
    notifications = installNotificationMock();
    silenceAudioPlayers();
    // Register the Android impl so resolvePlatformSpecificImplementation works;
    // its channel is the one mocked above.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    alarms = G7AlarmManager(
      FlutterLocalNotificationsPlugin(),
      await CgmStore.open(),
    );
    await alarms.init();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('trendArrow buckets the per-minute trend', () {
    test('maps each rate to its arrow', () {
      expect(alarms.trendArrow(2.5), '↑');
      expect(alarms.trendArrow(1.0), '↗');
      expect(alarms.trendArrow(0.0), '→');
      expect(alarms.trendArrow(-1.5), '↘');
      expect(alarms.trendArrow(-3.0), '↓');
    });
  });

  group('check is edge-triggered', () {
    test('fires once on entering a zone, not on staying in it', () async {
      await alarms.check(60, -1.0); // low warning
      await alarms.check(58, -1.0); // still low warning
      expect(notifications.shown, [G7AlarmLevel.lowWarning.index]);
    });

    test('fires again when the zone changes', () async {
      await alarms.check(60, -1.0); // low warning
      await alarms.check(50, -1.0); // urgent low
      expect(notifications.shown, [
        G7AlarmLevel.lowWarning.index,
        G7AlarmLevel.lowUrgent.index,
      ]);
    });

    test('an in-range reading raises nothing', () async {
      await alarms.check(100, 0.0);
      expect(notifications.shown, isEmpty);
    });

    test(
      'silent mode suppresses the notification but still tracks the zone',
      () async {
        storage['silent_mode'] = 'true';
        await alarms.check(60, -1.0);
        expect(notifications.shown, isEmpty);
        // Leaving silent: a value still in the SAME zone must not re-fire.
        storage['silent_mode'] = 'false';
        await alarms.check(58, -1.0);
        expect(notifications.shown, isEmpty);
        // Only a fresh crossing fires.
        await alarms.check(50, -1.0);
        expect(notifications.shown, [G7AlarmLevel.lowUrgent.index]);
      },
    );

    test('muting only the tones still shows the notification', () async {
      storage['silent_tones'] = 'true';
      await alarms.check(60, -1.0);
      expect(notifications.shown, [G7AlarmLevel.lowWarning.index]);
    });

    test('a null reading is ignored', () async {
      await alarms.check(null, 0.0);
      expect(notifications.shown, isEmpty);
    });
  });

  /// One low, one alarm per zone it reaches. Defaults are 55/70/180/250 with a
  /// 10 mg/dL re-arm margin, so a low is only over at 80 and an urgent low at 65
  /// — everything in between is still the same episode.
  group('an alarm is withdrawn once it stops being true', () {
    /// Just the glucose alarms: ids 0-4, everything from 100 up is another
    /// notification (a firing alarm also withdraws the pre-warning it fulfils).
    List<int> cancelledAlarms() =>
        notifications.cancelled.where((id) => id < 100).toList();

    test('recovering into range clears both alarm notifications', () async {
      await alarms.check(60, -1.0); // low warning
      await alarms.check(50, -1.0); // urgent low
      await alarms.check(100, 1.0); // recovered
      expect(cancelledAlarms(), [
        G7AlarmLevel.lowWarning.index,
        G7AlarmLevel.lowUrgent.index,
        G7AlarmLevel.highWarning.index,
        G7AlarmLevel.highUrgent.index,
      ]);
    });

    test('easing off inside the zone keeps the alarm standing', () async {
      await alarms.check(50, -1.0); // urgent low
      await alarms.check(65, 1.0); // low warning, still out of range
      expect(cancelledAlarms(), isEmpty);
    });

    test('a value wobbling back over the line does not clear it', () async {
      await alarms.check(60, -1.0); // low warning
      await alarms.check(72, 1.0); // inside the re-arm margin
      expect(cancelledAlarms(), isEmpty);
    });

    test('staying in range clears nothing a second time', () async {
      await alarms.check(60, -1.0);
      await alarms.check(100, 1.0);
      notifications.cancelled.clear();
      await alarms.check(105, 0.0);
      expect(cancelledAlarms(), isEmpty);
    });
  });

  group('one excursion alarms once per zone', () {
    test('a value wobbling around the line does not re-alarm', () async {
      await alarms.check(68, -1.0); // low warning
      await alarms.check(75, 1.0); // over the line, but not recovered
      await alarms.check(68, -1.0); // back under it — same low
      await alarms.check(72, 1.0);
      expect(notifications.shown, [G7AlarmLevel.lowWarning.index]);
    });

    test('a real recovery re-arms the zone', () async {
      await alarms.check(68, -1.0);
      await alarms.check(85, 1.0); // clear of the line by the margin
      await alarms.check(68, -1.0);
      expect(notifications.shown, [
        G7AlarmLevel.lowWarning.index,
        G7AlarmLevel.lowWarning.index,
      ]);
    });

    test('climbing back out of an urgent low says nothing', () async {
      await alarms.check(68, -1.0); // low warning
      await alarms.check(50, -1.0); // urgent low
      await alarms.check(60, 1.0); // recovering, still urgent's episode
      await alarms.check(68, 1.0); // back to a plain low — not news
      expect(notifications.shown, [
        G7AlarmLevel.lowWarning.index,
        G7AlarmLevel.lowUrgent.index,
      ]);
    });

    test('dropping deeper still alarms at once', () async {
      await alarms.check(68, -1.0);
      await alarms.check(50, -2.0);
      expect(notifications.shown.last, G7AlarmLevel.lowUrgent.index);
    });

    test('the high side holds its line the same way', () async {
      await alarms.check(185, 1.0); // high warning
      await alarms.check(175, -1.0); // under the line, not yet recovered
      await alarms.check(185, 1.0); // same high
      expect(notifications.shown, [G7AlarmLevel.highWarning.index]);
      await alarms.check(165, -1.0); // clear of it by the margin
      await alarms.check(185, 1.0);
      expect(notifications.shown.length, 2);
    });

    test('a low straight after a high is its own alarm', () async {
      await alarms.check(185, -2.0);
      await alarms.check(65, -2.0);
      expect(notifications.shown, [
        G7AlarmLevel.highWarning.index,
        G7AlarmLevel.lowWarning.index,
      ]);
    });
  });

  group('event log groups an excursion into one event', () {
    Future<List<String>> eventTypes() async {
      final store = await CgmStore.open();
      return store
          .eventsBetween(
            DateTime.fromMillisecondsSinceEpoch(0),
            DateTime.now().add(const Duration(days: 1)),
          )
          .map((event) => event.type)
          .toList();
    }

    test(
      'escalating within an out-of-range spell logs only one event',
      () async {
        await alarms.check(60, -1.0); // low warning → new event
        await alarms.check(50, -1.0); // urgent low → same spell, no new event
        await alarms.check(60, 1.0); // back to warning → still the same spell
        expect(await eventTypes(), ['glucose_low']);
      },
    );

    test('a fresh event only after glucose recovered into range', () async {
      await alarms.check(60, -1.0); // low → event
      await alarms.check(100, 1.0); // back in range
      await alarms.check(60, -1.0); // low again → second event
      expect(await eventTypes(), ['glucose_low', 'glucose_low']);
    });
  });

  group('a single alarm can have its tone switched off', () {
    test('the notification still shows without its tone', () async {
      storage['alarm_tone_low_warning'] = AlarmTone.off.name;
      await alarms.check(60, -1.0);
      expect(notifications.shown, [G7AlarmLevel.lowWarning.index]);
    });

    test('the other alarms keep theirs', () async {
      storage['alarm_tone_low_warning'] = AlarmTone.off.name;
      expect(
        await ProfileAlarmToneState().assetFor(AlarmSlot.lowUrgent),
        isNotNull,
      );
    });
  });

  group('a high alarm offers the correction it calls for', () {
    /// A paired pod is the precondition for the button: the delivery path
    /// refuses to write insulin nobody injected (see `AdvisoryActionRunner`).
    void pairPod() {
      storage['pod.unique_id'] = '12345';
      storage['pod.ltk'] = base64Encode(List.filled(16, 7));
    }

    test('a paired pod and a dose above zero get the button', () async {
      pairPod();
      await alarms.check(300, 1.0);
      expect(notifications.actions[G7AlarmLevel.highUrgent.index], 1);
    });

    test(
      'a correction already covered by insulin on board offers none',
      () async {
        pairPod();
        await const MealStore().saveMeals([
          Meal(
            time: DateTime.now(),
            carbs: 0,
            glucoseMgdl: 200,
            bolus: 20,
            entries: [],
          ),
        ]);
        await alarms.check(300, 1.0);
        expect(notifications.shown, [G7AlarmLevel.highUrgent.index]);
        expect(notifications.actions[G7AlarmLevel.highUrgent.index], 0);
      },
    );

    test('no pod paired means no button, however high the value', () async {
      await alarms.check(200, 1.0);
      expect(notifications.shown, [G7AlarmLevel.highWarning.index]);
      expect(notifications.actions[G7AlarmLevel.highWarning.index], 0);
    });

    test('a low alarm never carries one', () async {
      await alarms.check(50, -1.0);
      expect(notifications.actions[G7AlarmLevel.lowUrgent.index], 0);
    });

    test('the test alarm from the settings page carries none', () async {
      await alarms.fireTest(high: true);
      expect(notifications.actions[G7AlarmLevel.highWarning.index], 0);
    });
  });

  group('the pre-warning does not outlive what it warns about', () {
    /// Notification ids: 104 is the pre-warning, 105 the report on a
    /// countermeasure accepted from it.
    const advisoryId = 104;
    const outcomeId = 105;

    test('the countermeasure is named by the button alone', () async {
      await alarms.checkAdvisory(110, -3.0);
      expect(notifications.actions[advisoryId], 1);
      // The body says what glucose is doing, once: no second sentence
      // repeating what the button already offers.
      expect(notifications.bodies[advisoryId], isNot(contains('\n')));
    });

    test('it carries the timeout Android withdraws it by', () async {
      await alarms.checkAdvisory(110, -3.0);
      expect(notifications.shown, [advisoryId]);
      expect(
        notifications.timeouts[advisoryId],
        AdvisoryRequest.validFor.inMilliseconds,
      );
    });

    test('a forecast back in the clear withdraws it at once', () async {
      await alarms.checkAdvisory(110, -3.0);
      await alarms.checkAdvisory(120, 0.0);
      expect(notifications.cancelled, contains(advisoryId));
    });

    test('the report on a delivered countermeasure keeps standing', () async {
      await alarms.notifyAdvisoryOutcome('alarm.advisory.carbs_logged', [10]);
      expect(notifications.timeouts[outcomeId], isNull);
    });
  });

  group('fireTest previews an alarm regardless of zone/silent', () {
    test('high test shows the high-warning notification', () async {
      storage['silent_mode'] = 'true';
      await alarms.fireTest(high: true);
      expect(notifications.shown, [G7AlarmLevel.highWarning.index]);
    });
  });

  group('connection-lost warning', () {
    test(
      'fires once after the outage threshold and clears on a reading',
      () async {
        await alarms.checkConnectionLost(
          sensorLinked: true,
          sinceLastReading: const Duration(minutes: 20),
        );
        await alarms.checkConnectionLost(
          sensorLinked: true,
          sinceLastReading: const Duration(minutes: 25),
        );
        expect(notifications.shown, hasLength(1));
        await alarms.onReading();
        expect(notifications.cancelled, hasLength(1));
      },
    );

    test('stays quiet before the threshold or with no sensor', () async {
      await alarms.checkConnectionLost(
        sensorLinked: true,
        sinceLastReading: const Duration(minutes: 5),
      );
      await alarms.checkConnectionLost(
        sensorLinked: false,
        sinceLastReading: const Duration(hours: 1),
      );
      expect(notifications.shown, isEmpty);
    });
  });

  group('sensor-expiry warning is one-shot per sensor', () {
    test('fires once when under 24 h remain, then stays persisted', () async {
      final store = await CgmStore.open();
      Future<void> tick() => alarms.checkExpiry(
        store: store,
        key: 'SERIAL',
        sessionLengthSec: 864000,
        secsSinceStart: 864000 - 3600, // 1 h left
      );
      await tick();
      await tick();
      expect(notifications.shown, hasLength(1));
      expect(store.expiryNotified('SERIAL'), isTrue);
    });

    test('does not fire while plenty of session remains', () async {
      final store = await CgmStore.open();
      await alarms.checkExpiry(
        store: store,
        key: 'SERIAL',
        sessionLengthSec: 864000,
        secsSinceStart: 0,
      );
      expect(notifications.shown, isEmpty);
    });
  });

  group('halftime reminder', () {
    const session = 864000; // 10 d
    const half = session ~/ 2;

    test('fires once just after the halfway crossing', () async {
      final store = await CgmStore.open();
      Future<void> tick(int secsSinceStart) => alarms.checkHalftime(
        store: store,
        key: 'SERIAL',
        sessionLengthSec: session,
        secsSinceStart: secsSinceStart,
      );
      await tick(half - 300); // still first half → nothing
      await tick(half + 300); // just past half → fires
      await tick(half + 600); // already notified → nothing
      expect(notifications.shown, [103]);
    });

    test(
      'never fires deep into the second half, even if not yet notified',
      () async {
        final store = await CgmStore.open();
        await alarms.checkHalftime(
          store: store,
          key: 'SERIAL',
          sessionLengthSec: session,
          secsSinceStart: half + 3 * 86400, // day 8 → outside the window
        );
        expect(notifications.shown, isEmpty);
      },
    );
  });
}
