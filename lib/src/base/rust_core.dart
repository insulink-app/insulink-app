import 'package:insulink/src/rust/frb_generated.dart';

/// Brings up the Rust bridge once per isolate, whoever asks first.
///
/// [RustLib.init] throws if it runs twice, and each isolate needs its own call:
/// the CGM service does it in `CgmTaskHandler.onStart`, but the UI isolate had
/// no reason to until the pod arrived. Pod PAIRING is the one thing in the UI
/// isolate that needs Rust, for the X25519 exchange, and without this it fails
/// with "flutter_rust_bridge has not been initialized" the moment the pod is
/// found.
///
/// Lazy rather than done at launch, because a user with no pod should not pay
/// for it. The future is shared, so concurrent callers wait on one init, and a
/// failed one is forgotten so the next attempt can retry rather than inheriting
/// the failure forever.
class RustCore {
  static Future<void>? _starting;

  static Future<void> ensureInitialised() {
    return _starting ??= RustLib.init().catchError((Object error) {
      _starting = null;
      throw error;
    });
  }
}
