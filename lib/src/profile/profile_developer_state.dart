import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether developer mode is enabled. Gates developer-only UI such as the
/// connection log on the sensor page. Provided above the page tree so any page
/// can observe it; persisted in secure storage.
class ProfileDeveloperState extends ChangeNotifier {
  static const _key = "developer";

  bool _enabled;

  ProfileDeveloperState(bool enabled) : _enabled = enabled;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    const storage = FlutterSecureStorage();
    await storage.write(key: _key, value: value.toString());
  }

  /// Read the persisted flag (defaults to off).
  static Future<bool> load() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: _key) == "true";
  }
}
