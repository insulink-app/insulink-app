import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of `flutter drive`: stores each screenshot the app takes under
/// `build/screenshots/`, named by the path the test gives it.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [arguments]) async {
    final file = File('build/screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
