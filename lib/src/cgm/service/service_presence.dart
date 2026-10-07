import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Whether the foreground service is up, asked from the UI isolate.
///
/// The browser demo has no service and no plugin behind the channel, where
/// `FlutterForegroundTask.isRunningService` throws a `MissingPluginException`;
/// there the answer is simply no.
class ServicePresence {
  const ServicePresence();

  Future<bool> get running async =>
      !kIsWeb && await FlutterForegroundTask.isRunningService;
}
