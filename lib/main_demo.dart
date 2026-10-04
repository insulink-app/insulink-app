import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:insulink/main.dart';
import 'package:insulink/src/demo/demo_account.dart';
import 'package:insulink/src/demo/demo_backend.dart';
import 'package:insulink/src/demo/demo_launch.dart';
import 'package:insulink/src/localization/locales.dart';

/// Entry point of the browser demo on the project website (`docs/WEB_DEMO.md`).
///
/// Unlike `main.dart` it loads no vendor keys and opens no foreground-service
/// port (the browser has no isolates for it). The whole app runs inside
/// `runWithClient`, so every request it makes is answered by [DemoBackend] and
/// never reaches the Insulink API. The binding is created inside that zone too,
/// so frame callbacks, and with them every request a widget starts, stay in it.
///
/// The website passes its language and theme as `?lang=&theme=`. Locales are
/// initialised after [DemoLaunch] has stored them, since they read the stored
/// language once.
Future<void> main() async {
  final network = Client();
  final account = DemoAccount(DateTime.now());
  final page = Uri.base.queryParameters;
  await runWithClient(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await DemoLaunch(
      account,
      language: page['lang'],
      theme: page['theme'],
    ).prepare();
    await Locales.init(["de", "en"]);
    runApp(const InsulinkApp());
  }, () => DemoBackend(account: account, network: network));
}
