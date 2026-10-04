import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/auth/account_sync.dart';
import 'package:insulink/src/demo/demo_account.dart';
import 'package:insulink/src/demo/demo_layouts.dart';
import 'package:insulink/src/demo/demo_pump.dart';
import 'package:insulink/src/demo/demo_sensor.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';

/// Puts the browser demo into the state of a signed-in user who has used the
/// app for a month: a clean storage, setup done, the embedding page's language
/// and theme, Google Health connected, the website's box layouts, every
/// collection pulled from the demo backend through the app's own sync code, a
/// paired sensor and a running pod.
class DemoLaunch {
  DemoLaunch(this.account, {required this.language, required this.theme});

  final DemoAccount account;

  /// `de`/`en` and `dark`/`light` from the website (the iframe's query), or null
  /// to fall back to the browser's own, like a fresh install.
  final String? language;
  final String? theme;

  static const _languages = {'de', 'en'};
  static const _themes = {'dark', 'light'};

  static const _storage = FlutterSecureStorage();

  Future<void> prepare() async {
    await _storage.deleteAll();
    await _skipSetup();
    await _adoptPage();
    await _connectGoogleHealth();
    await DemoLayouts().arrange();
    await AccountSync().pullAll(null, withHistory: true);
    await DemoSensor(account.glucose).pair();
    await DemoPump(account.now, account.glucose.readings).attach();
  }

  /// Legal notice and permission onboarding done, signed in as "Demo", meals
  /// shown on the glucose chart, and no fingerprint gates, since a browser has no biometrics to ask. The token is
  /// never sent anywhere: the demo backend answers every request.
  Future<void> _skipSetup() async {
    await _storage.write(key: 'legal_accepted', value: 'true');
    await _storage.write(key: 'onboarding_done', value: 'true');
    await _storage.write(key: 'authentication_token', value: 'demo');
    await _storage.write(key: 'name', value: 'Demo');
    await _storage.write(key: 'chart_show_meals', value: 'true');
    for (final action in GuardedAction.values) {
      await ProfileSecurityState().setGuarded(action, false);
    }
  }

  /// Takes over the website's language and theme, so the demo matches the page
  /// around it.
  Future<void> _adoptPage() async {
    if (_languages.contains(language)) {
      await _storage.write(key: 'language', value: language);
    }
    if (_themes.contains(theme)) {
      await _storage.write(key: 'theme', value: theme);
    }
  }

  /// Connected, so its boxes show the pulled days; a fresh import stamp, so the
  /// app does not try Health Connect, which the browser does not have; and the
  /// newest pulse sample as the band's live heart rate, which the day pull keeps.
  Future<void> _connectGoogleHealth() async {
    await _storage.write(key: 'google_health.connected', value: 'true');
    await _storage.write(
      key: 'google_health.last_import',
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await _storage.write(
      key: 'google_health.data',
      value: jsonEncode({
        'days': <Object>[],
        'hr': account.latestPulse['b'],
        'hrAt': account.latestPulse['t'],
      }),
    );
  }
}
