import 'package:flutter/foundation.dart';

/// Whether the last request of this isolate reached the Insulink server: true
/// after any reply below 500, false after a timeout, a transport failure or a
/// server error, null before the first attempt (and for good in guest mode,
/// where nothing is sent). The header's account badge draws it.
///
/// Passive on purpose: the app's own syncs keep it current, so nothing polls.
// ponytail: per isolate, the service isolate's uploads do not count; add a
// cross-isolate ping only if a UI that sits idle for long shows a stale dot.
class ServerReachability extends ValueNotifier<bool?> {
  ServerReachability._() : super(null);

  static final ServerReachability shared = ServerReachability._();

  /// Records one finished attempt: [statusCode] of the reply, or null when
  /// there was none.
  void record(int? statusCode) {
    value = statusCode != null && statusCode < 500;
  }
}
