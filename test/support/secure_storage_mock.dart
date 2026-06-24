import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backs flutter_secure_storage with an in-memory map so code that persists via
/// it can be unit-tested without the platform keystore. Returns the backing map
/// so a test can seed/inspect it (e.g. the `language` key).
Map<String, String> installSecureStorageMock() {
  final backing = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'write':
            backing[args['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            return backing[args['key'] as String];
          case 'delete':
            backing.remove(args['key'] as String);
            return null;
          case 'readAll':
            return Map<String, String>.from(backing);
          case 'deleteAll':
            backing.clear();
            return null;
          case 'containsKey':
            return backing.containsKey(args['key'] as String);
        }
        return null;
      });
  return backing;
}
