import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:insulink/main.dart';
import 'package:insulink/src/demo/demo_account.dart';
import 'package:insulink/src/demo/demo_backend.dart';
import 'package:insulink/src/demo/demo_launch.dart';
import 'package:insulink/src/localization/locales.dart';

/// The app on the demo account, shared by the website's entry point
/// (`lib/main_demo.dart`) and the screenshot run
/// (`integration_test/screenshots_test.dart`).
///
/// Everything runs inside [inZone], so every request is answered by
/// [DemoBackend] and never reaches the Insulink API. The binding has to be
/// created inside that zone too, so frame callbacks, and with them every
/// request a widget starts, stay in it.
class DemoApp {
  DemoApp({required this.language, required this.theme});

  /// `de`/`en` and `dark`/`light`, or null for the browser's own.
  final String? language;
  final String? theme;

  final DemoAccount account = DemoAccount(DateTime.now());

  /// A client created OUTSIDE the zone, for map tiles and the food database.
  final Client _network = Client();

  R inZone<R>(R Function() body) => runWithClient(
    body,
    () => DemoBackend(account: account, network: _network),
  );

  /// Signs in, pulls the account and shows the app. Locales are initialised
  /// after [DemoLaunch] has stored the language, since they read it once.
  Future<void> start() async {
    await DemoLaunch(account, language: language, theme: theme).prepare();
    await Locales.init(["de", "en"]);
    runApp(const InsulinkApp());
  }
}
