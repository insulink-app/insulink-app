import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/pump/loop/loop_decision.dart';
import 'package:insulink/src/pump/loop/loop_settings.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// The loop builds several of its keys from enum values at runtime, so a value
/// added later would render as a raw key on screen and nothing would fail. The
/// key-parity test cannot see these, because it only compares the two files
/// against each other, and both would be missing the same key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> localeFile(String language) async {
    final raw = await rootBundle.loadString('assets/locales/$language.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Walks a dotted path, honouring the convention that a node which is both a
  /// label and a prefix keeps its own value under `_`.
  bool hasKey(Map<String, dynamic> locale, String path) {
    dynamic node = locale;
    for (final part in path.split('.')) {
      if (node is! Map<String, dynamic> || !node.containsKey(part)) {
        return false;
      }
      node = node[part];
    }
    return node is String || (node is Map && node['_'] is String);
  }

  final expectedKeys = <String>[
        'pump.loop.title',
        'pump.loop.last',
        'pump.loop.no_cycle',
        'pump.loop.journal',
        'pump.loop.not_sent',
        'pump.loop.at_glucose',
        'pump.loop.on_board',
        'pump.loop.schedule_was',
        'pump.loop.auth_reason',
        'pump.loop.warning.title',
        'pump.loop.warning.body',
        'pump.loop.warning.confirm',
        'pump.loop.blocked.no_pod',
        'pump.loop.blocked.no_schedule',
        'pump.loop.blocked.limits',
        'alarm.pod.loop_stopped.title',
        'profile.loop',
        'profile.loop.description',
        for (final mode in PodLoopMode.values) ...[
          'pump.loop.mode.${mode.name}',
          'pump.loop.hint.${mode.name}',
        ],
        for (final reason in LoopReason.values)
          'pump.loop.reason.${reason.localeKey}',
        for (final bound in LoopBound.values)
          'pump.loop.bound.${bound.localeKey}',
        for (final stop in PodLoopStop.values)
          'pump.loop.stopped.${stop.localeKey}',
        for (final setting in LoopSettings.all) ...[
          setting.labelKey,
          setting.valueKey,
        ],
      ];

  for (final language in ['de', 'en']) {
    test('every key the automation renders exists in $language', () async {
      final locale = await localeFile(language);

      for (final key in expectedKeys) {
        expect(hasKey(locale, key), isTrue, reason: '$key is missing');
      }
    });
  }

  test('enum names become snake_case keys', () {
    expect(LoopBound.hypoHeadroom.localeKey, 'hypo_headroom');
    expect(LoopReason.holdingSchedule.localeKey, 'holding_schedule');
    expect(PodLoopStop.podUnreachable.localeKey, 'pod_unreachable');
    expect(PodLoopMode.off.localeKey, 'off');
  });
}
