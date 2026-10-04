/// Whether this build is the browser demo on the project website: dummy data,
/// no backend, no vendor keys. Set with `--dart-define=DEMO=true` and built from
/// `lib/main_demo.dart` (see `docs/WEB_DEMO.md`).
class DemoMode {
  static const bool enabled = bool.fromEnvironment('DEMO');
}
