import 'package:flutter/widgets.dart';
import 'package:insulink/src/demo/demo_app.dart';

/// Entry point of the browser demo on the project website (`docs/WEB_DEMO.md`).
/// The website passes its language and theme as `?lang=&theme=`.
///
/// Unlike `main.dart` it loads no vendor keys and opens no foreground-service
/// port (the browser has no isolates for it).
Future<void> main() {
  final page = Uri.base.queryParameters;
  final demo = DemoApp(language: page['lang'], theme: page['theme']);
  return demo.inZone(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await demo.start();
  });
}
